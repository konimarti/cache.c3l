// Copyright (c) 2025 Koni Marti. All rights reserved.
// Use of this source code is governed by the MIT license
// a copy of which can be found in the LICENSE_STDLIB file.
<*
 Implementation of LRU and LFU Caches.
 @require $defined((Key){}.hash()) : `No .hash function found on the key`
*>
module std::collections::cache{Key, Value};

import std::collections::map;
import std::collections::pair;
import std::io;

const Allocator CACHE_HEAP_ALLOCATOR = (Allocator)&dummy;
const LRUCache ONHEAP_LRU = { .allocator = CACHE_HEAP_ALLOCATOR };
const LFUCache ONHEAP_LFU = { .allocator = CACHE_HEAP_ALLOCATOR };

const uint DEFAULT_INITIAL_CAPACITY = 16;

alias CacheMap @private = HashMap{ Key, Node* };
alias FreqMap @private = HashMap{ usz, Pair{ Node*, Node* } };
alias OnEvictCallback = fn void (Key, Value, void*);

struct Node @private
{
	Key   key;
	Value value;
	usz   freq; // Only used for LFU Cache
	Node* prev;
	Node* next;
}

fn Node* Node.init(&self, Key key, Value value) @private
{
	*self = { .key = key, .value = value, .freq = 1, .prev = null, .next = null };
	return self;
}

Node head @private = (Node){};
Node tail @private = (Node){};

<*
 Implements a LRU cache eviction strategy that drops the least recently used
 data if capacity is reached. `get` and `set` run in constant time O(1).
*>
struct LRUCache (Printable)
{
	CacheMap    map;
	Node*       head;
	Node*       tail;
	Allocator   allocator;
	usz         capacity;
	OnEvictCallback on_evict_fn;
	void*       evict_data;
}

<*
 @param [&inout] allocator : "The allocator to use"
 @require capacity > 0 : "The capacity must be 1 or higher"
*>
fn LRUCache* LRUCache.init(&self,
	Allocator allocator,
	uint capacity = DEFAULT_INITIAL_CAPACITY,
	OnEvictCallback on_evict_fn = null,
	void* evict_data = null)
{
	self.map.init(allocator);

	self.head = &head;
	self.tail = &tail;
	self.head.next = self.tail;
	self.tail.prev = self.head;

	self.allocator = allocator;
	self.capacity = capacity;
	self.on_evict_fn = on_evict_fn;
	self.evict_data = evict_data;
	return self;
}

<*
 @require capacity > 0 : "The capacity must be 1 or higher"
*>
fn LRUCache* LRUCache.tinit(&self, uint capacity = DEFAULT_INITIAL_CAPACITY)
{
	return self.init(tmem, capacity) @inline;
}

fn void LRUCache.free(&self, uint capacity = DEFAULT_INITIAL_CAPACITY)
{
	if (!self.allocator) return;
	self.map.@each(; Key key, Node* node){
		self.evict_node(node);
	};
	self.map.free();
	*self = {};
}

<*
 Prints the LRUCache line-by-line. The first lines have the highest recency.
*>
fn usz? LRUCache.to_format(&self, Formatter *f) @dynamic
{
	usz n;
	Node *ptr = self.head.next;
	n += f.printf("Key        Value\n")!;
	n += f.printf("---------- ----------")!;
	while (ptr != self.tail)
	{
		n += f.printf("%10.10s %s\n", ptr.key, ptr.value)!;
		ptr = ptr.next;
	}
	return n;
}


fn Value? LRUCache.get(&self, Key key) @operator([])
{
	if (try node = self.map.get(key))
	{
		// Promote node to the front.
		self.remove_node(node);
		self.insert_node(node);
		return node.value;
	}
	return NOT_FOUND?;
}

fn bool LRUCache.has_key(&self, Key key) => self.map.has_key(key);

fn bool LRUCache.set(&self, Key key, Value value) @operator([]=)
{
	// If the map isn't initialized, use the defaults to initialize it.
	switch (self.allocator.ptr)
	{
		case &dummy: self.init(mem);
		case null: self.tinit();
		default: break;
	}

	if (try node = self.map.get(key))
	{
		self.remove_node(node);
		self.map.remove(key);
		self.evict_node(node);
	}

	if (self.map.len() >= self.capacity)
	{
		Node* lru = self.tail.prev;
		self.remove_node(lru);
		self.map.remove(lru.key);
		self.evict_node(lru);
	}

	Node* new_node = allocator::new(self.allocator, Node);
	new_node.init(key, value);
	self.insert_node(new_node);
	self.map.set(key, new_node);
	return true;
}

<*
 Add node at the front of the linked list.
*>
fn void LRUCache.insert_node(&self, Node *node) @private
{
	Node* next_node = self.head.next;
	self.head.next = node;
	node.prev = self.head;
	node.next = next_node;
	next_node.prev = node;
}

<*
 Remove node from linked list.
*>
fn void LRUCache.remove_node(&self, Node *node) @private
{
	Node* prev_node, next_node;
	prev_node = node.prev;
	next_node = node.next;
	prev_node.next = next_node;
	next_node.prev = prev_node;;
}

<*
 Evict node: Run on_evict_fn if defined and free node.
*>
fn void LRUCache.evict_node(&self, Node* node) @private
{
	if (self.on_evict_fn) {
		self.on_evict_fn(node.key, node.value, self.evict_data);
	}
	allocator::free(self.allocator, node);
}

<*
 Implements a LFU cache eviction strategy that drops the least frequently used
 data if capacity is reached. `get` and `set` run in constant time O(1).
*>
struct LFUCache (Printable)
{
	CacheMap    map;
	FreqMap     freq;
	Allocator   allocator;
	usz         capacity; // Number of elements
	usz         min_freq;
	OnEvictCallback on_evict_fn;
	void*       evict_data;
}

<*
 @param [&inout] allocator : "The allocator to use"
 @require capacity > 0 : "The capacity must be 1 or higher"
*>
fn LFUCache* LFUCache.init(&self,
	Allocator allocator,
	usz capacity = DEFAULT_INITIAL_CAPACITY,
	OnEvictCallback on_evict_fn = null,
	void* evict_data = null)
{
	self.map.init(allocator);
	self.freq.init(allocator);

	self.allocator = allocator;
	self.capacity = capacity;
	self.min_freq = 0;;
	self.on_evict_fn = on_evict_fn;
	self.evict_data = evict_data;
	return self;
}

<*
 @require capacity > 0 : "The capacity must be 1 or higher"
*>
fn LFUCache* LFUCache.tinit(&self, usz capacity = DEFAULT_INITIAL_CAPACITY)
{
	return self.init(tmem, capacity) @inline;
}

fn void LFUCache.free(&self, uint capacity = DEFAULT_INITIAL_CAPACITY)
{
	if (!self.allocator) return;

	self.map.@each(; Key key, Node* node){
		self.evict_node(node);
	};
	self.map.free();

	self.freq.@each(; ulong k, Pair{Node*,Node*} v){
		allocator::free(self.allocator, v.first);
		allocator::free(self.allocator, v.second);
	};
	self.freq.free();

	*self = {};
}


<*
 Prints the LFUCache.
*>
fn usz? LFUCache.to_format(&self, Formatter *f) @dynamic
{
	usz n;
	n += f.printf("Frequency  Key        Value")!;
	n += f.printf("---------- ---------- ----------")!;
	self.freq.@each(; ulong freq, Pair{Node*,Node*} v)
	{
		Node* ptr = v.first.next;
		while (ptr != v.second)
		{
			n += f.printf("%10d %10.10s %s ", freq, ptr.key, ptr.value)!;
			ptr = ptr.next;
		}
		n += f.print("\n")!;
	};
	return n;
}

fn Value? LFUCache.get(&self, Key key) @operator([])
{
	if (try node = self.map.get(key)) {
		Value value = node.value;
		self.update_frequencies(node);
		return value;
	}
	return NOT_FOUND?;
}

fn bool LFUCache.has_key(&self, Key key) => self.map.has_key(key);

fn bool LFUCache.set(&self, Key key, Value value) @operator([]=)
{
	// If the map isn't initialized, use the defaults to initialize it.
	switch (self.allocator.ptr)
	{
		case &dummy: self.init(mem);
		case null: self.tinit();
		default: break;
	}

	if (try node = self.map.get(key))
	{
		if (self.on_evict_fn)
		{
			// If an eviction function is defined, we call it to
			// release value before it is overwritten.
			self.on_evict_fn(node.key, node.value, self.evict_data);
		}
		node.value = value;
		self.update_frequencies(node);
	}
	else
	{
		// Remove least frequently used data if cache is full
		if (self.map.len() >= self.capacity)
		{
			if (try freq_list = self.freq[self.min_freq])
			{
				Node *lfu = freq_list.second.prev;
				self.map.remove(lfu.key);
				self.remove_node(lfu);
				self.evict_node(lfu);

				if (freq_list.first.next == freq_list.second)
				{
					allocator::free(self.allocator, freq_list.first);
					allocator::free(self.allocator, freq_list.second);
					self.freq.remove(self.min_freq);
				}
			}
		}
	}

	Node* new_node = allocator::new(self.allocator, Node);
	new_node.init(key, value);
	self.map.set(key, new_node);
	self.min_freq = 1;
	self.insert_node(new_node, 1);
	return true;
}

<*
 Add node at the front of the linked list for the given frequency.
*>
fn void LFUCache.insert_node(&self, Node *node, usz freq) @private
{
	if (catch self.freq[freq])
	{
		Node *head = allocator::new(self.allocator, Node);
		Node *tail = allocator::new(self.allocator, Node);
		head.next = tail;
		tail.prev = head;
		self.freq[freq] = { head, tail };
	}

	// This next line can never panic becaus it will be set above.
	Node *head = self.freq[freq]!!.first;
	Node *tmp  = head.next;
	node.next = tmp;
	node.prev = head;
	head.next = node;
	tmp.prev = node;
}

<*
 Remove node from linked list.
*>
fn void LFUCache.remove_node(&self, Node *node) @private
{
	Node* prev_node, next_node;
	prev_node = node.prev;
	next_node = node.next;
	prev_node.next = next_node;
	next_node.prev = prev_node;;
}

<*
 Update frequencies for a given node and it to the linked list.
*>
fn void LFUCache.update_frequencies(&self, Node* node) @private
{
	usz old_freq = node.freq;
	node.freq++;

	self.remove_node(node); // Remove from current list

	if (try flist = self.freq[old_freq] && flist.first.next == flist.second)
	{
		allocator::free(self.allocator, flist.first);
		allocator::free(self.allocator, flist.second);
		self.freq.remove(old_freq);
		if (self.min_freq == old_freq) self.min_freq++;
	}

	self.insert_node(node, node.freq);
}

<*
 Evict node: Run on_evict_fn if defined and free node.
*>
fn void LFUCache.evict_node(&self, Node* node) @private
{
	if (self.on_evict_fn) {
		self.on_evict_fn(node.key, node.value, self.evict_data);
	}
	allocator::free(self.allocator, node);
}


int dummy @local;
