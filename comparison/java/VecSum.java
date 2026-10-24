// Reconstructed from the video at 09:46; validation and optional arguments were added.
import java.util.*;
import java.util.stream.*;

public class VecSum {
    public static long sum(int[] arr) {
        return Arrays.stream(arr).parallel().sum();
    }

    public static void main(String[] args) {
        if (args.length > 3) throw new IllegalArgumentException("expected: elements iterations workers");
        int n = args.length > 0 ? Integer.parseInt(args[0]) : 200_000_000;
        int iter = args.length > 1 ? Integer.parseInt(args[1]) : 500;
        if (n < 0 || n > 200_000_000 || iter < 1 || iter > 100_000)
            throw new IllegalArgumentException("invalid size or iterations");
        if (args.length > 2) {
            int workers = Integer.parseInt(args[2]);
            if (workers < 1 || workers > 64) throw new IllegalArgumentException("invalid workers");
            System.setProperty("java.util.concurrent.ForkJoinPool.common.parallelism", Integer.toString(workers - 1));
        }
        int[] arr = new int[n];
        Arrays.fill(arr, 2);
        List<Double> times = new ArrayList<>();
        long result = -1;
        for (int i = 0; i < iter; ++i) {
            long start = System.nanoTime();
            long sum = sum(arr);
            long end = System.nanoTime();
            if (sum != (long)n * 2) throw new AssertionError("wrong sum");
            if (i == 0) result = sum;
            times.add((end - start) / 1_000_000.0);
        }
        List<Double> sorted = times.stream().sorted().collect(Collectors.toList());
        double avg = times.stream().mapToDouble(Double::doubleValue).average().orElse(0);
        double median = sorted.get(iter / 2);
        System.out.printf(Locale.ROOT, "Workers: %s%nFirst time: %.3f ms%nAverage time: %.3f ms%nMedian time: %.3f ms%nSum: %d%n",
            args.length > 2 ? args[2] : "default", times.get(0), avg, median, result);
    }
}
