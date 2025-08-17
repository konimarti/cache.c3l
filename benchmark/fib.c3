import std::collections::cache;

fn void init() @init
{
    set_benchmark_warmup_iterations(5);
    set_benchmark_max_iterations(256);
}

alias FibCache = LRUCache{int, int};
const N = 32;

fn void slow_fib_bench() @benchmark => (void)slow_fib(N);
fn void memo_fib_bench() @benchmark
{
	FibCache cache;
	cache.init(mem, 4);
	(void)memo_fib(N, &cache);
	cache.free();
}

fn int slow_fib(int n)
{
    if (n <= 1) return n;
    return slow_fib(n - 1) + slow_fib(n - 2);
}

fn int memo_fib(int n, FibCache *cache)
{
    if (try out = cache.get(n)) return out;

    int v = (n <= 1) ? n : memo_fib(n - 1, cache) + memo_fib(n - 2, cache);
    cache.set(n, v);
    return v;
}

