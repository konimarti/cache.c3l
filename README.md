# LRU/LFU Cache in C3

A zero-dependency **Least Recently Used (LRU) and Least Frequently Used (LFU)
cache** for [C3](https://c3-lang.org/). It provides O(1) `get`/`set` by
combining a hash map with a doubly-linked list.

> Works well for memoization, caching decoded assets, small DB query results, etc.

---

## Features

* **O(1)** `get`, `set`
* **Generic** over key and value types
* **Eviction callback** (e.g., to free resources)
* **No dependencies**; portable C3

---

## How it works

* A **hash map** gives constant-time lookup.
* A **doubly-linked list** maintains recency: most-recently-used at the head, least at the tail.
* On `get`, we move the node to the head.
  On `set`:
  * If key exists: update value and move to head.
  * If capacity reached: evict the tail and free that node.

---

## Install

Add the module from this repo to your project:

```bash
# clone into your project
git submodule add https://github.com/konimarti/cache.c3l lib/cache.c3l
# build normally
c3c build
```

Import it in C3:

```c3
import std::collections::cache; 
```

---

## Usage examples

### 1) Basic LRU cache of `String → int`

```c3
import std::collections::cache;
import std::io;

fn void main() => example_basic();

fn void example_basic() => @assert_leak()
{
	// Create a cache with capacity 3
	LRUCache{String, int} lru;
	lru.init(mem, 3);
	defer lru.free();

	lru["one"] = 1;
	lru["two"] = 2;
	lru["three"] = 3;

	if (try lru["two"])
	{
	// Accessing 'two' makes it most-recently-used
	}

	// Insert a 4th item, this evicts least-recently-used (key "one")
	lru["four"] = 4;

	if (@catch(lru["one"]))
	{
		io::printn("1 was evicted");
	}
}
```

### 2) Eviction callback example (freeing heap resources)

```c3
fn void on_evict_free_string(String k, String v, void* data) => v.free(mem);

fn void test_lru_cache_custom_free() @test
{
	LRUCache{String, String} lru;
	lru.init(mem, 2, &on_evict_free_string);

	lru.set("A", "FOO".copy(mem));
	lru.set("B", "BAR".copy(mem));

	assert(lru.get("A")!! == "FOO");

	lru.set("C", "FFF".copy(mem)); // evict B
	assert(@catch(lru.get("B")));

	lru.set("D", "BBB".copy(mem)); // evict A
	assert(@catch(lru.get("A")));

	assert(@ok(lru.get("C")));
	assert(@ok(lru.get("D")));

	lru.free();
}
```

---

## Limitations & notes

* Values are stored **by value**. If you put pointers, **you** own the lifetime (use `on_evict_fn`).
* The `on_evict_fn` is also called when a value is overwritten by resetting an existing key (for the LFU cache).
* Not persistent; state is in-memory only.
* This implementation is **not** thread-safe. Wrap it with your own mutex/RWLock if you need concurrent access.

---

## License

MIT. See `LICENSE`.
