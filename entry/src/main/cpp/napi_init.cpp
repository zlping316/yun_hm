#include <atomic>
#include <cerrno>
#include <cstdint>
#include <fcntl.h>
#include <memory>
#include <mutex>
#include <string>
#include <sys/stat.h>
#include <unistd.h>
#include <unordered_map>
#include <vector>

#include "multimedia/player_framework/native_avbuffer.h"
#include "multimedia/player_framework/native_avcodec_base.h"
#include "multimedia/player_framework/native_avdemuxer.h"
#include "multimedia/player_framework/native_avformat.h"
#include "multimedia/player_framework/native_avmuxer.h"
#include "multimedia/player_framework/native_avsource.h"
#include "napi/native_api.h"

namespace {

constexpr int32_t DEFAULT_SAMPLE_CAPACITY = 16 * 1024 * 1024;
constexpr int32_t MAX_TRACK_COUNT = 32;

struct TrackState {
    uint32_t sourceIndex = 0;
    uint32_t muxerIndex = 0;
    OH_AVBuffer *buffer = nullptr;
    OH_AVCodecBufferAttr attr {};
    bool pending = false;
    bool ended = false;
};

struct RemuxWork {
    napi_async_work asyncWork = nullptr;
    napi_deferred deferred = nullptr;
    int64_t taskId = 0;
    std::string inputPath;
    std::string outputPath;
    std::atomic_bool canceled {false};
    int64_t outputSize = 0;
    std::string error;
};

std::atomic_int64_t gNextTaskId {1};
std::mutex gWorkMutex;
std::unordered_map<int64_t, RemuxWork *> gWorks;

std::string AvError(const std::string &stage, OH_AVErrCode code)
{
    return stage + " failed, code=" + std::to_string(static_cast<int32_t>(code));
}

void CleanupTracks(std::vector<TrackState> &tracks)
{
    for (TrackState &track : tracks) {
        if (track.buffer != nullptr) {
            OH_AVBuffer_Destroy(track.buffer);
            track.buffer = nullptr;
        }
    }
}

bool ReadNextSample(OH_AVDemuxer *demuxer, TrackState &track, std::string &error)
{
    if (track.ended || track.pending) {
        return true;
    }
    const OH_AVErrCode code = OH_AVDemuxer_ReadSampleBuffer(demuxer, track.sourceIndex, track.buffer);
    if (code != AV_ERR_OK) {
        error = AvError("read sample track " + std::to_string(track.sourceIndex), code);
        return false;
    }
    if (OH_AVBuffer_GetBufferAttr(track.buffer, &track.attr) != AV_ERR_OK) {
        error = "get sample attributes failed for track " + std::to_string(track.sourceIndex);
        return false;
    }
    if ((track.attr.flags & AVCODEC_BUFFER_FLAGS_EOS) != 0) {
        track.ended = true;
        return true;
    }
    if (track.attr.size > 0) {
        track.pending = true;
    }
    return true;
}

bool Remux(RemuxWork &work)
{
    int inputFd = -1;
    int outputFd = -1;
    OH_AVSource *source = nullptr;
    OH_AVDemuxer *demuxer = nullptr;
    OH_AVMuxer *muxer = nullptr;
    bool muxerStarted = false;
    std::vector<TrackState> tracks;
    bool success = false;

    struct stat inputStat {};
    inputFd = open(work.inputPath.c_str(), O_RDONLY);
    if (inputFd < 0 || fstat(inputFd, &inputStat) != 0 || inputStat.st_size <= 0) {
        work.error = "open input failed, errno=" + std::to_string(errno);
        goto cleanup;
    }
    outputFd = open(work.outputPath.c_str(), O_CREAT | O_TRUNC | O_RDWR, 0644);
    if (outputFd < 0) {
        work.error = "open output failed, errno=" + std::to_string(errno);
        goto cleanup;
    }

    source = OH_AVSource_CreateWithFD(inputFd, 0, inputStat.st_size);
    if (source == nullptr) {
        work.error = "create AVSource failed";
        goto cleanup;
    }
    demuxer = OH_AVDemuxer_CreateWithSource(source);
    if (demuxer == nullptr) {
        work.error = "create AVDemuxer failed";
        goto cleanup;
    }
    muxer = OH_AVMuxer_Create(outputFd, AV_OUTPUT_FORMAT_MPEG_4);
    if (muxer == nullptr) {
        work.error = "create AVMuxer failed";
        goto cleanup;
    }

    {
        OH_AVFormat *sourceFormat = OH_AVSource_GetSourceFormat(source);
        int32_t trackCount = 0;
        if (sourceFormat == nullptr ||
            !OH_AVFormat_GetIntValue(sourceFormat, OH_MD_KEY_TRACK_COUNT, &trackCount) ||
            trackCount <= 0 || trackCount > MAX_TRACK_COUNT) {
            if (sourceFormat != nullptr) {
                OH_AVFormat_Destroy(sourceFormat);
            }
            work.error = "invalid source track count";
            goto cleanup;
        }
        OH_AVFormat_Destroy(sourceFormat);

        for (int32_t index = 0; index < trackCount; ++index) {
            OH_AVFormat *trackFormat = OH_AVSource_GetTrackFormat(source, static_cast<uint32_t>(index));
            if (trackFormat == nullptr) {
                work.error = "get track format failed for track " + std::to_string(index);
                goto cleanup;
            }
            int32_t trackType = -1;
            const bool hasTrackType = OH_AVFormat_GetIntValue(trackFormat, OH_MD_KEY_TRACK_TYPE, &trackType);
            if (!hasTrackType || (trackType != MEDIA_TYPE_AUD && trackType != MEDIA_TYPE_VID)) {
                OH_AVFormat_Destroy(trackFormat);
                continue;
            }

            int32_t muxerTrackIndex = -1;
            OH_AVErrCode code = OH_AVMuxer_AddTrack(muxer, &muxerTrackIndex, trackFormat);
            int32_t sampleCapacity = DEFAULT_SAMPLE_CAPACITY;
            int32_t declaredCapacity = 0;
            if (OH_AVFormat_GetIntValue(trackFormat, OH_MD_KEY_MAX_INPUT_SIZE, &declaredCapacity) &&
                declaredCapacity > sampleCapacity) {
                sampleCapacity = declaredCapacity;
            }
            OH_AVFormat_Destroy(trackFormat);
            if (code != AV_ERR_OK || muxerTrackIndex < 0) {
                work.error = AvError("add track " + std::to_string(index), code);
                goto cleanup;
            }
            code = OH_AVDemuxer_SelectTrackByID(demuxer, static_cast<uint32_t>(index));
            if (code != AV_ERR_OK) {
                work.error = AvError("select track " + std::to_string(index), code);
                goto cleanup;
            }
            OH_AVBuffer *buffer = OH_AVBuffer_Create(sampleCapacity);
            if (buffer == nullptr) {
                work.error = "create sample buffer failed for track " + std::to_string(index);
                goto cleanup;
            }
            tracks.push_back({
                static_cast<uint32_t>(index),
                static_cast<uint32_t>(muxerTrackIndex),
                buffer,
                {},
                false,
                false
            });
        }
    }

    if (tracks.empty()) {
        work.error = "source contains no MP4-compatible audio or video track";
        goto cleanup;
    }
    {
        const OH_AVErrCode code = OH_AVMuxer_Start(muxer);
        if (code != AV_ERR_OK) {
            work.error = AvError("start muxer", code);
            goto cleanup;
        }
        muxerStarted = true;
    }

    {
        bool timestampBaseSet = false;
        int64_t timestampBase = 0;
        while (!work.canceled.load()) {
            bool hasActiveTrack = false;
            int32_t selectedTrack = -1;
            int64_t selectedPts = INT64_MAX;
            for (size_t index = 0; index < tracks.size(); ++index) {
                TrackState &track = tracks[index];
                if (!ReadNextSample(demuxer, track, work.error)) {
                    goto cleanup;
                }
                if (!track.ended) {
                    hasActiveTrack = true;
                }
                if (track.pending && track.attr.pts < selectedPts) {
                    selectedPts = track.attr.pts;
                    selectedTrack = static_cast<int32_t>(index);
                }
            }
            if (selectedTrack < 0) {
                if (!hasActiveTrack) {
                    success = true;
                    break;
                }
                continue;
            }
            TrackState &track = tracks[static_cast<size_t>(selectedTrack)];
            if (!timestampBaseSet) {
                timestampBase = track.attr.pts;
                timestampBaseSet = true;
            }
            OH_AVCodecBufferAttr adjustedAttr = track.attr;
            adjustedAttr.pts = adjustedAttr.pts > timestampBase ? adjustedAttr.pts - timestampBase : 0;
            if (OH_AVBuffer_SetBufferAttr(track.buffer, &adjustedAttr) != AV_ERR_OK) {
                work.error = "set sample attributes failed for track " + std::to_string(track.sourceIndex);
                goto cleanup;
            }
            const OH_AVErrCode code =
                OH_AVMuxer_WriteSampleBuffer(muxer, track.muxerIndex, track.buffer);
            if (code != AV_ERR_OK) {
                work.error = AvError("write sample track " + std::to_string(track.sourceIndex), code);
                goto cleanup;
            }
            track.pending = false;
        }
    }

    if (work.canceled.load()) {
        work.error = "remux canceled";
        success = false;
    }

cleanup:
    if (muxerStarted) {
        const OH_AVErrCode stopCode = OH_AVMuxer_Stop(muxer);
        if (success && stopCode != AV_ERR_OK) {
            work.error = AvError("stop muxer", stopCode);
            success = false;
        }
    }
    CleanupTracks(tracks);
    if (muxer != nullptr) {
        OH_AVMuxer_Destroy(muxer);
    }
    if (demuxer != nullptr) {
        OH_AVDemuxer_Destroy(demuxer);
    }
    if (source != nullptr) {
        OH_AVSource_Destroy(source);
    }
    if (outputFd >= 0) {
        close(outputFd);
    }
    if (inputFd >= 0) {
        close(inputFd);
    }

    if (success) {
        struct stat outputStat {};
        if (stat(work.outputPath.c_str(), &outputStat) != 0 || outputStat.st_size <= 0) {
            work.error = "output MP4 is empty";
            success = false;
        } else {
            work.outputSize = outputStat.st_size;
        }
    }
    if (!success) {
        unlink(work.outputPath.c_str());
    }
    return success;
}

bool GetString(napi_env env, napi_value value, std::string &result)
{
    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok) {
        return false;
    }
    result.resize(length + 1);
    if (napi_get_value_string_utf8(env, value, result.data(), result.size(), &length) != napi_ok) {
        return false;
    }
    result.resize(length);
    return true;
}

void ExecuteRemux(napi_env, void *data)
{
    Remux(*static_cast<RemuxWork *>(data));
}

void CompleteRemux(napi_env env, napi_status status, void *data)
{
    auto *work = static_cast<RemuxWork *>(data);
    {
        std::lock_guard<std::mutex> lock(gWorkMutex);
        gWorks.erase(work->taskId);
    }
    if (status == napi_ok && work->error.empty() && work->outputSize > 0) {
        napi_value value = nullptr;
        napi_create_int64(env, work->outputSize, &value);
        napi_resolve_deferred(env, work->deferred, value);
    } else {
        const std::string message = work->error.empty() ? "native remux task failed" : work->error;
        napi_value messageValue = nullptr;
        napi_value errorValue = nullptr;
        napi_create_string_utf8(env, message.c_str(), NAPI_AUTO_LENGTH, &messageValue);
        napi_create_error(env, nullptr, messageValue, &errorValue);
        napi_reject_deferred(env, work->deferred, errorValue);
    }
    napi_delete_async_work(env, work->asyncWork);
    delete work;
}

napi_value StartRemux(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc != 2) {
        napi_throw_type_error(env, nullptr, "startRemux requires inputPath and outputPath");
        return nullptr;
    }

    auto work = std::make_unique<RemuxWork>();
    if (!GetString(env, argv[0], work->inputPath) || !GetString(env, argv[1], work->outputPath)) {
        napi_throw_type_error(env, nullptr, "inputPath and outputPath must be strings");
        return nullptr;
    }
    work->taskId = gNextTaskId.fetch_add(1);

    napi_value promise = nullptr;
    napi_create_promise(env, &work->deferred, &promise);
    napi_value resourceName = nullptr;
    napi_create_string_utf8(env, "SystemMp4Remux", NAPI_AUTO_LENGTH, &resourceName);
    if (napi_create_async_work(
            env, nullptr, resourceName, ExecuteRemux, CompleteRemux, work.get(), &work->asyncWork) != napi_ok ||
        napi_queue_async_work(env, work->asyncWork) != napi_ok) {
        napi_throw_error(env, nullptr, "failed to queue native remux task");
        return nullptr;
    }

    {
        std::lock_guard<std::mutex> lock(gWorkMutex);
        gWorks[work->taskId] = work.get();
    }
    napi_value result = nullptr;
    napi_value taskIdValue = nullptr;
    napi_create_object(env, &result);
    napi_create_int64(env, work->taskId, &taskIdValue);
    napi_set_named_property(env, result, "taskId", taskIdValue);
    napi_set_named_property(env, result, "promise", promise);
    work.release();
    return result;
}

napi_value CancelRemux(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    int64_t taskId = 0;
    if (argc == 1 && napi_get_value_int64(env, argv[0], &taskId) == napi_ok) {
        std::lock_guard<std::mutex> lock(gWorkMutex);
        const auto iterator = gWorks.find(taskId);
        if (iterator != gWorks.end()) {
            iterator->second->canceled.store(true);
        }
    }
    napi_value result = nullptr;
    napi_get_undefined(env, &result);
    return result;
}

napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor descriptors[] = {
        {"startRemux", nullptr, StartRemux, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"cancelRemux", nullptr, CancelRemux, nullptr, nullptr, nullptr, napi_default, nullptr}
    };
    napi_define_properties(env, exports, sizeof(descriptors) / sizeof(descriptors[0]), descriptors);
    return exports;
}

} // namespace

static napi_module gModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "mp4remux",
    .nm_priv = nullptr,
    .reserved = {nullptr}
};

extern "C" __attribute__((constructor)) void RegisterMp4RemuxModule()
{
    napi_module_register(&gModule);
}
