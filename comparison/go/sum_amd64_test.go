package main

import "testing"

func TestSumNEON(t *testing.T) {
	values := make([]int32, 132)
	for i := range values {
		values[i] = int32(i%17 - 8)
	}
	for offset := 0; offset < 4; offset++ {
		for n := 0; n <= 128; n++ {
			var expected int64
			for _, value := range values[offset : offset+n] {
				expected += int64(value)
			}
			if actual := sumNEON(values[offset : offset+n]); actual != expected {
				t.Fatalf("offset=%d length=%d: got %d want %d", offset, n, actual, expected)
			}
		}
	}
	if result := sumNEON([]int32{1_000_000_000, 1_000_000_000, 1_000_000_000, 1_000_000_000}); result != 4_000_000_000 {
		t.Fatalf("64-bit lane reduction: got %d", result)
	}
}
