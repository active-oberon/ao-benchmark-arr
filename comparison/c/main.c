/* Reconstructed C control: the video's C source is not shown; the SIMD shape follows Cython at 09:07. */
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <errno.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>
#include "neon_compat.h"

typedef struct { const int32_t *data; size_t count; int64_t sum; } Worker;

static int64_t sum_simd(const int32_t *arr, size_t n) {
    int32x4_t a = vdupq_n_s32(0), b = a, c = a, d = a;
    size_t i = 0;
    for (; i + 16 <= n; i += 16) {
        a = vaddq_s32(a, vld1q_s32(arr + i));
        b = vaddq_s32(b, vld1q_s32(arr + i + 4));
        c = vaddq_s32(c, vld1q_s32(arr + i + 8));
        d = vaddq_s32(d, vld1q_s32(arr + i + 12));
    }
    int64_t sum = vaddvq_s32(vaddq_s32(vaddq_s32(a, b), vaddq_s32(c, d)));
    for (; i < n; ++i) sum += arr[i];
    return sum;
}

static void *worker(void *arg) {
    Worker *w = arg;
    w->sum = sum_simd(w->data, w->count);
    return NULL;
}

static void check_pthread(int error) {
    if (error) { errno = error; perror("pthread"); exit(1); }
}

static int64_t parallel_sum(const int32_t *arr, size_t n, size_t threads) {
    pthread_t handles[64];
    Worker workers[64];
    size_t chunk = (n + threads - 1) / threads;
    for (size_t i = 0; i < threads; ++i) {
        size_t start = i * chunk;
        if (start > n) start = n;
        size_t count = n - start;
        if (count > chunk) count = chunk;
        workers[i] = (Worker){arr + start, count, 0};
        check_pthread(pthread_create(&handles[i], NULL, worker, &workers[i]));
    }
    int64_t result = 0;
    for (size_t i = 0; i < threads; ++i) {
        check_pthread(pthread_join(handles[i], NULL));
        result += workers[i].sum;
    }
    return result;
}

static uint64_t now_ns(void) {
    struct timespec t;
    if (clock_gettime(CLOCK_MONOTONIC, &t)) { perror("clock_gettime"); exit(1); }
    return (uint64_t)t.tv_sec * 1000000000 + t.tv_nsec;
}

static size_t argument(int argc, char **argv, int index, size_t fallback, size_t min, size_t max) {
    if (argc <= index) return fallback;
    char *end;
    errno = 0;
    unsigned long value = strtoul(argv[index], &end, 10);
    if (errno || *end || end == argv[index] || value < min || value > max) {
        fprintf(stderr, "invalid argument: %s\n", argv[index]); exit(2);
    }
    return value;
}

static int compare(const void *a, const void *b) {
    double x = *(const double *)a, y = *(const double *)b;
    return (x > y) - (x < y);
}

int main(int argc, char **argv) {
    if (argc > 4) return 2;
    long cpus = sysconf(_SC_NPROCESSORS_ONLN);
    size_t n = argument(argc, argv, 1, 200000000, 0, 200000000);
    size_t iterations = argument(argc, argv, 2, 500, 1, 100000);
    size_t threads = argument(argc, argv, 3, cpus > 0 ? (size_t)cpus : 1, 1, 64);
    int32_t *arr = malloc((n ? n : 1) * sizeof(*arr));
    double *durations = malloc(iterations * sizeof(*durations));
    if (!arr || !durations) { perror("malloc"); free(arr); free(durations); return 1; }
    for (size_t i = 0; i < n; ++i) arr[i] = 2;
    int64_t result = 0;
    double mean = 0;
    for (size_t i = 0; i < iterations; ++i) {
        uint64_t start = now_ns();
        result = parallel_sum(arr, n, threads);
        durations[i] = (now_ns() - start) / 1000000.0;
        assert(result == (int64_t)n * 2);
        mean += durations[i];
    }
    printf("Workers: %zu\nFirst time: %.3f ms\n", threads, durations[0]);
    qsort(durations, iterations, sizeof(*durations), compare);
    printf("Average time: %.3f ms\nMedian time: %.3f ms\nSum: %lld\n",
           mean / iterations, durations[iterations / 2], (long long)result);
    free(durations); free(arr);
}
