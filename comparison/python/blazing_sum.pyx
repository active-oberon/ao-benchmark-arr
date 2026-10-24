# Reconstructed from 09:07-09:25; neon_compat.h preserves 128-bit vector operations on x86-64.
# cython: language_level=3, boundscheck=False, wraparound=False
from libc.stdlib cimport malloc, free
from libc.stdint cimport int32_t
from cython.parallel cimport prange

cdef extern from "neon_compat.h":
    ctypedef struct int32x4_t:
        pass
    int32x4_t vdupq_n_s32(int) noexcept nogil
    int32x4_t vld1q_s32(const int32_t*) noexcept nogil
    int32x4_t vaddq_s32(int32x4_t, int32x4_t) noexcept nogil
    int32_t vaddvq_s32(int32x4_t) noexcept nogil

cdef int32_t* data = NULL
cdef int length = 0

cdef long neon_sum(int32_t* arr, int n) noexcept nogil:
    cdef int i
    cdef int32x4_t accA = vdupq_n_s32(0)
    cdef int32x4_t accB = vdupq_n_s32(0)
    cdef int32x4_t accC = vdupq_n_s32(0)
    cdef int32x4_t accD = vdupq_n_s32(0)
    for i in range(0, n - n % 16, 16):
        accA = vaddq_s32(accA, vld1q_s32(&arr[i]))
        accB = vaddq_s32(accB, vld1q_s32(&arr[i + 4]))
        accC = vaddq_s32(accC, vld1q_s32(&arr[i + 8]))
        accD = vaddq_s32(accD, vld1q_s32(&arr[i + 12]))
    cdef int32x4_t accAB = vaddq_s32(accA, accB)
    cdef int32x4_t accCD = vaddq_s32(accC, accD)
    cdef int32x4_t acc = vaddq_s32(accAB, accCD)
    cdef long total = vaddvq_s32(acc)
    for i in range(n - n % 16, n):
        total += arr[i]
    return total

cdef long neon_sum_par(int32_t* arr, int n, int num_chunks) noexcept nogil:
    cdef int chunk_size = (n + num_chunks - 1) // num_chunks
    cdef int i, start, count
    cdef long total = 0
    for i in prange(num_chunks, schedule='static', num_threads=num_chunks):
        start = min(n, i * chunk_size)
        count = min(chunk_size, n - start)
        total += neon_sum(arr + start, count)
    return total

def prepare(int n):
    global data, length
    if n < 0 or n > 200000000:
        raise ValueError("invalid size")
    close()
    data = <int32_t*>malloc(max(n, 1) * sizeof(int32_t))
    if data == NULL:
        raise MemoryError("malloc failed")
    length = n
    cdef int i
    for i in range(n):
        data[i] = 2

def parallel_sum(int workers=16):
    if workers < 1 or workers > 64 or data == NULL:
        raise ValueError("invalid workers or uninitialized array")
    cdef long result
    with nogil:
        result = neon_sum_par(data, length, workers)
    return result

def close():
    global data, length
    free(data)
    data = NULL
    length = 0
