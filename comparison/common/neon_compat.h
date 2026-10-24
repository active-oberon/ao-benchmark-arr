#ifndef NEON_COMPAT_H
#define NEON_COMPAT_H
#include <stdint.h>
#if defined(__aarch64__)
#include <arm_neon.h>
#else
#include <emmintrin.h>
typedef __m128i int32x4_t;
static inline int32x4_t vdupq_n_s32(int value) { return _mm_set1_epi32(value); }
static inline int32x4_t vld1q_s32(const int32_t *p) { return _mm_loadu_si128((const __m128i *)p); }
static inline int32x4_t vaddq_s32(int32x4_t a, int32x4_t b) { return _mm_add_epi32(a, b); }
static inline int32_t vaddvq_s32(int32x4_t a) {
    a = _mm_add_epi32(a, _mm_srli_si128(a, 8));
    a = _mm_add_epi32(a, _mm_srli_si128(a, 4));
    return _mm_cvtsi128_si32(a);
}
#endif
#endif
