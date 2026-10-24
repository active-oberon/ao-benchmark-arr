// Reconstructed from the video at 11:37; arguments only replace the displayed constants.
use std::{env, thread, time::Instant};

fn process_mt(arr: &'static [i32], workers: usize) -> i32 {
    arr.chunks(arr.len().div_ceil(workers).max(1))
        .map(|chunk| thread::spawn(move || chunk.iter().sum::<i32>()))
        .collect::<Vec<_>>()
        .into_iter()
        .map(|h| h.join().unwrap())
        .sum()
}

fn main() {
    let args: Vec<String> = env::args().collect();
    assert!(args.len() <= 4);
    let argument = |i: usize, fallback: usize| {
        args.get(i).map(|s| s.parse::<usize>().expect("invalid argument")).unwrap_or(fallback)
    };
    let n = argument(1, 200_000_000);
    let iterations = argument(2, 500);
    let workers = argument(3, 12);
    assert!(n <= 200_000_000 && (1..=100_000).contains(&iterations) && (1..=64).contains(&workers));
    let arr = Box::leak(vec![2_i32; n].into_boxed_slice());
    let mut durations = Vec::with_capacity(iterations);
    let mut result = 0;
    for _ in 0..iterations {
        let start = Instant::now();
        result = process_mt(arr, workers);
        durations.push(start.elapsed().as_secs_f64() * 1000.0);
        assert_eq!(result, n as i32 * 2);
    }
    println!("Workers: {}\nFirst time: {:.3} ms", workers, durations[0]);
    durations.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let mean = durations.iter().sum::<f64>() / durations.len() as f64;
    let median = durations[durations.len() / 2];
    println!("Average time: {:.3} ms\nMedian time: {:.3} ms\nSum: {}", mean, median, result);
}
