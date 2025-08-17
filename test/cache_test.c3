module std::collections::cache_test @test;

import std::collections::cache;

fn void test_lru_cache() => @pool()
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
