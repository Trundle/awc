#pragma once

#include <stdint.h>
#include <drm_fourcc.h>

// For some weird reason, Swift doesn't find DRM_FORMAT_ARGB8888 :/
static const uint32_t _DRM_FORMAT_ARGB8888 = DRM_FORMAT_ARGB8888;
