// Reconstructed from the video at 03:18; amd64 SIMD replaces the displayed ARM64 NEON kernel.
package main

import (
	"fmt"
	"os"
	"runtime"
	"slices"
	"strconv"
	"sync"
	"time"
)

// sumNEON keeps the video's interface while the amd64 implementation uses SSE2.
func sumNEON(arr []int32) int64

func processGoroutinesASM(arr []int32, numWorkers int) int64 {
	chunkSize := (len(arr) + numWorkers - 1) / numWorkers
	var wg sync.WaitGroup
	results := make(chan int64, numWorkers)
	for i := 0; i < numWorkers; i++ {
		start := i * chunkSize
		if start > len(arr) {
			start = len(arr)
		}
		wg.Add(1)
		go func(start int) {
			defer wg.Done()
			end := min(start+chunkSize, len(arr))
			results <- sumNEON(arr[start:end])
		}(start)
	}
	wg.Wait()
	close(results)
	var result int64
	for value := range results {
		result += value
	}
	return result
}

func main() {
	settings := []int{200_000_000, 500, runtime.NumCPU() * 2}
	if len(os.Args) > 4 {
		panic("expected: elements iterations workers")
	}
	for i, argument := range os.Args[1:] {
		value, err := strconv.Atoi(argument)
		if err != nil {
			panic(err)
		}
		settings[i] = value
	}
	n, iterations, workers := settings[0], settings[1], settings[2]
	if n < 0 || n > 200_000_000 || iterations < 1 || iterations > 100_000 || workers < 1 || workers > 64 {
		panic("invalid arguments")
	}
	arr := make([]int32, n)
	for i := range arr {
		arr[i] = 2
	}
	times := make([]float64, iterations)
	var result int64
	var total float64
	for i := range times {
		start := time.Now()
		result = processGoroutinesASM(arr, workers)
		times[i] = float64(time.Since(start).Nanoseconds()) / 1_000_000
		if result != int64(n)*2 {
			panic("wrong sum")
		}
		total += times[i]
	}
	fmt.Printf("Workers: %d\nFirst time: %.3f ms\n", workers, times[0])
	slices.Sort(times)
	fmt.Printf("Average time: %.3f ms\nMedian time: %.3f ms\nSum: %d\n", total/float64(iterations), times[iterations/2], result)
}
