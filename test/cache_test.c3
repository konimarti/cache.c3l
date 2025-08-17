module std::collections::cache_test;

import std::collections::cache;

fn void test_lru_cache() @test => @pool()
{
	LRUCache{String, int} lru;
	lru.tinit(2);
	lru.set("A", 1);
	lru.set("B", 2);
	assert(lru.get("A")!! == 1);
	lru.set("C", 3);
	assert(@catch(lru.get("B")));
	lru.set("D", 4);
	assert(@catch(lru.get("A")));
	assert(@ok(lru.get("C")));
	assert(@ok(lru.get("D")));
}

fn void on_evict_free_string(String k, String v, void* data) => v.free(mem);

fn void test_lru_cache_custom_free() @test
{
	LRUCache{String, String} lru;
	lru.init(mem, 2, &on_evict_free_string);
	lru.set("A", "FOO".copy(mem));
	lru.set("B", "BAR".copy(mem));
	assert(lru.get("A")!! == "FOO");
	lru.set("C", "FFF".copy(mem));
	assert(@catch(lru.get("B")));
	lru.set("D", "BBB".copy(mem));
	assert(@catch(lru.get("A")));
	assert(@ok(lru.get("C")));
	assert(@ok(lru.get("D")));
	lru.free();
}
