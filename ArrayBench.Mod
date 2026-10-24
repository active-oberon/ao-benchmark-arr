MODULE ArrayBench;

IMPORT SYSTEM, Commands, Machine, PrecisionTimer, FoxArrayBaseOptimized;

CONST
	Elements = 200000000;
	Iterations = 500;
	CalibrationRuns = 7;

TYPE
	Buffer = OBJECT
	VAR values: ARRAY [*] OF SIGNED32;
		PROCEDURE &Init(count: SIZE);
		BEGIN NEW(values, count)
		END Init;
	END Buffer;
	Workers = POINTER TO ARRAY OF Worker;

	Worker = OBJECT
	VAR
		data: Buffer;
		first, count: SIZE;
		pending, done, stopping, exited, useAVX2: BOOLEAN;
		result: SIGNED32;

		PROCEDURE &Init(data: Buffer; first, count: SIZE; useAVX2: BOOLEAN);
		BEGIN
			SELF.data := data; SELF.first := first; SELF.count := count; SELF.useAVX2 := useAVX2
		END Init;

		PROCEDURE Start;
		BEGIN {EXCLUSIVE}
			ASSERT(~pending & ~stopping);
			done := FALSE; pending := TRUE
		END Start;

		PROCEDURE Join(): SIGNED32;
		BEGIN {EXCLUSIVE}
			AWAIT(done);
			RETURN result
		END Join;

		PROCEDURE Stop;
		BEGIN {EXCLUSIVE}
			stopping := TRUE;
			AWAIT(exited)
		END Stop;

	BEGIN {ACTIVE}
		LOOP
			BEGIN {EXCLUSIVE}
				AWAIT(pending OR stopping);
				IF stopping THEN exited := TRUE; EXIT END;
				pending := FALSE
			END;
			result := Sum(data.values, first, count, useAVX2);
			BEGIN {EXCLUSIVE} done := TRUE END
		END
	END Worker;

(* HasAVX2 checks both CPU instructions and operating system vector state before using YMM registers. *)
PROCEDURE HasAVX2(): BOOLEAN;
CODE {SYSTEM.AMD64}
	PUSH RBX
	XOR EAX, EAX
	CPUID
	CMP EAX, 7
	JL unavailable
	MOV EAX, 1
	CPUID
	AND ECX, 018000000H
	CMP ECX, 018000000H
	JNE unavailable
	XOR ECX, ECX
	DB 00FH, 001H, 0D0H ; XGETBV is absent from the Fox mnemonic table.
	AND EAX, 6
	CMP EAX, 6
	JNE unavailable
	MOV EAX, 7
	XOR ECX, ECX
	CPUID
	TEST EBX, 020H
	JZ unavailable
	MOV EAX, 1
	JMP finish
unavailable:
	XOR EAX, EAX
finish:
	POP RBX
END HasAVX2;

(* SumAVX2 uses four independent accumulators to read 32 integers per iteration without a serial addition chain. *)
PROCEDURE SumAVX2(address: ADDRESS; count: SIZE): SIGNED32;
CODE {SYSTEM.AMD64}
	MOV RSI, [RBP + address]
	MOV RCX, [RBP + count]
	VPXOR YMM0, YMM0, YMM0
	VPXOR YMM1, YMM1, YMM1
	VPXOR YMM2, YMM2, YMM2
	VPXOR YMM3, YMM3, YMM3
loop32:
	CMP RCX, 32
	JL reduce
	VPADDD YMM0, YMM0, [RSI]
	VPADDD YMM1, YMM1, [RSI + 32]
	VPADDD YMM2, YMM2, [RSI + 64]
	VPADDD YMM3, YMM3, [RSI + 96]
	ADD RSI, 128
	SUB RCX, 32
	JMP loop32
reduce:
	VPADDD YMM0, YMM0, YMM1
	VPADDD YMM2, YMM2, YMM3
	VPADDD YMM0, YMM0, YMM2
loop8:
	CMP RCX, 8
	JL horizontal
	VPADDD YMM0, YMM0, [RSI]
	ADD RSI, 32
	SUB RCX, 8
	JMP loop8
horizontal:
	VEXTRACTI128 XMM1, YMM0, 1
	VPADDD XMM0, XMM0, XMM1
	VPHADDD XMM0, XMM0, XMM0
	VPHADDD XMM0, XMM0, XMM0
	VMOVD EAX, XMM0
tail:
	TEST RCX, RCX
	JZ finish
	ADD EAX, [RSI]
	ADD RSI, 4
	DEC RCX
	JMP tail
finish:
	VZEROUPPER
END SumAVX2;

PROCEDURE Sum(CONST data: ARRAY [*] OF SIGNED32; first, count: SIZE; useAVX2: BOOLEAN): SIGNED32;
BEGIN
	ASSERT((first >= 0) & (count >= 0) & (first <= LEN(data, 0)) & (count <= LEN(data, 0) - first));
	IF count = 0 THEN RETURN 0 END;
	IF useAVX2 THEN RETURN SumAVX2(ADDRESSOF(data[first]), count) END;
	RETURN SUM(data[first .. first + count - 1])
END Sum;

PROCEDURE OpenWorkers(data: Buffer; count: SIZE; useAVX2: BOOLEAN): Workers;
VAR workers: Workers; i, first, last: SIZE;
BEGIN
	ASSERT(count > 0);
	NEW(workers, count);
	FOR i := 0 TO count - 1 DO
		first := LEN(data.values, 0) * i DIV count;
		last := LEN(data.values, 0) * (i + 1) DIV count;
		NEW(workers[i], data, first, last - first, useAVX2)
	END;
	RETURN workers
END OpenWorkers;

PROCEDURE CloseWorkers(workers: Workers);
VAR i: SIZE;
BEGIN
	FOR i := 0 TO LEN(workers) - 1 DO workers[i].Stop END
END CloseWorkers;

PROCEDURE ParallelSum(workers: Workers): SIGNED32;
VAR i: SIZE; result: SIGNED32;
BEGIN
	FOR i := 0 TO LEN(workers) - 1 DO workers[i].Start END;
	result := 0;
	FOR i := 0 TO LEN(workers) - 1 DO INC(result, workers[i].Join()) END;
	RETURN result
END ParallelSum;

PROCEDURE Statistics(VAR durations: ARRAY OF PrecisionTimer.Counter; VAR mean, median: FLOAT64);
VAR i, j, middle: SIZE; value, total: PrecisionTimer.Counter;
BEGIN
	ASSERT(LEN(durations) > 0);
	total := 0;
	FOR i := 0 TO LEN(durations) - 1 DO INC(total, durations[i]) END;
	FOR i := 1 TO LEN(durations) - 1 DO
		value := durations[i]; j := i;
		WHILE (j > 0) & (durations[j - 1] > value) DO
			durations[j] := durations[j - 1]; DEC(j)
		END;
		durations[j] := value
	END;
	mean := FLOAT64(total) / LEN(durations);
	middle := LEN(durations) DIV 2;
	median := FLOAT64(durations[middle]);
	IF LEN(durations) MOD 2 = 0 THEN
		median := (median + FLOAT64(durations[middle - 1])) / 2
	END
END Statistics;

PROCEDURE Measure(data: Buffer; threads, iterations: SIZE; useAVX2: BOOLEAN;
	VAR mean, median: FLOAT64; VAR result: SIGNED32);
VAR workers: Workers; durations: POINTER TO ARRAY OF PrecisionTimer.Counter;
	i: SIZE; start: PrecisionTimer.Counter;
BEGIN
	ASSERT(iterations > 0);
	workers := OpenWorkers(data, threads, useAVX2);
	NEW(durations, iterations);
	FOR i := 1 TO 3 DO ASSERT(ParallelSum(workers) = 2 * LEN(data.values, 0)) END;
	FOR i := 0 TO iterations - 1 DO
		start := PrecisionTimer.GetCounter();
		result := ParallelSum(workers);
		durations[i] := PrecisionTimer.GetCounter() - start;
		ASSERT(result = 2 * LEN(data.values, 0));
		ASSERT(durations[i] > 0)
	END;
	CloseWorkers(workers);
	Statistics(durations^, mean, median)
END Measure;

PROCEDURE Run(useAVX2: BOOLEAN);
VAR data: Buffer; i, threads, cores, bestThreads: SIZE;
	mean, median, bestMedian, ticksPerMs: FLOAT64; result: SIGNED32; context: Commands.Context;
BEGIN
	context := Commands.GetContext();
	IF useAVX2 & ~HasAVX2() THEN
		context.error.String("ArrayBench requires x86-64 with AVX2 and OS support for YMM registers.");
		context.error.Ln; context.result := Commands.CommandError; RETURN
	END;
	ASSERT(PrecisionTimer.GetCounter() > 0);
	ticksPerMs := FLOAT64(PrecisionTimer.GetFrequency()) / 1000;
	cores := Machine.NumberOfProcessors();
	IF cores < 1 THEN cores := 1 END;
	NEW(data, Elements);
	data.values := 2;
	IF useAVX2 THEN context.out.String("Kernel: AVX2 CODE")
	ELSE context.out.String("Kernel: math arrays / SUM") END;
	context.out.Ln;
	context.out.String("Elements: "); context.out.Int(Elements, 0);
	context.out.String("; bytes: "); context.out.Int(Elements * 4, 0); context.out.Ln;
	context.out.String("Calibration: threads / median ms"); context.out.Ln;
	bestThreads := 1; bestMedian := MAX(FLOAT64);
	FOR threads := 1 TO cores DO
		Measure(data, threads, CalibrationRuns, useAVX2, mean, median, result);
		context.out.Int(threads, 0); context.out.String(" / ");
		context.out.FloatFix(median / ticksPerMs, 0, 3, 0); context.out.Ln; context.out.Update;
		IF median < bestMedian THEN bestMedian := median; bestThreads := threads END
	END;
	Measure(data, bestThreads, Iterations, useAVX2, mean, median, result);
	context.out.String("Threads: "); context.out.Int(bestThreads, 0);
	context.out.String("; iterations: "); context.out.Int(Iterations, 0); context.out.Ln;
	context.out.String("Average time: "); context.out.FloatFix(mean / ticksPerMs, 0, 3, 0);
	context.out.String(" ms"); context.out.Ln;
	context.out.String("Median time: "); context.out.FloatFix(median / ticksPerMs, 0, 3, 0);
	context.out.String(" ms"); context.out.Ln;
	context.out.String("Read bandwidth: ");
	context.out.FloatFix(FLOAT64(Elements) * 4 * PrecisionTimer.GetFrequency() / median / 1000000000, 0, 3, 0);
	context.out.String(" GB/s"); context.out.Ln;
	context.out.String("Sum: "); context.out.Int(result, 0); context.out.Ln
END Run;

PROCEDURE Do*;
BEGIN Run(TRUE)
END Do;

PROCEDURE Math*;
BEGIN Run(FALSE)
END Math;

PROCEDURE Check*;
VAR data: Buffer; workers: Workers; first, count, i, n, threads, mode: SIZE;
	expected: SIGNED32; mean, median: FLOAT64; times: ARRAY 4 OF PrecisionTimer.Counter;
BEGIN
	ASSERT(HasAVX2());
	NEW(data, 132);
	FOR i := 0 TO LEN(data.values, 0) - 1 DO data.values[i] := SIGNED32(i MOD 17) - 8 END;
	FOR first := 0 TO 3 DO
		FOR count := 0 TO 128 DO
			expected := 0;
			FOR i := first TO first + count - 1 DO INC(expected, data.values[i]) END;
			ASSERT(Sum(data.values, first, count, FALSE) = expected);
			ASSERT(Sum(data.values, first, count, TRUE) = expected)
		END
	END;
	ASSERT(Sum(data.values, LEN(data.values, 0), 0, FALSE) = 0);
	ASSERT(Sum(data.values, LEN(data.values, 0), 0, TRUE) = 0);
	FOR n := 0 TO 67 DO
		NEW(data, n);
		expected := 0;
		FOR i := 0 TO n - 1 DO data.values[i] := SIGNED32(i MOD 17) - 8; INC(expected, data.values[i]) END;
		FOR mode := 0 TO 1 DO
			FOR threads := 1 TO 3 DO
				workers := OpenWorkers(data, threads, mode = 1);
				FOR i := 1 TO 3 DO ASSERT(ParallelSum(workers) = expected) END;
				CloseWorkers(workers)
			END
		END
	END;
	times[0] := 4; times[1] := 1; times[2] := 3; times[3] := 2;
	Statistics(times, mean, median);
	ASSERT((mean = 2.5) & (median = 2.5));
	Commands.GetContext().out.String("PASS: SUM and AVX2 ranges, empty arrays, repeated parallel sums, mean and median.");
	Commands.GetContext().out.Ln
END Check;

END ArrayBench.
