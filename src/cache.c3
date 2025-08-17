// Copyright (c) 2025 Koni Marti. All rights reserved.
// Use of this source code is governed by the MIT license
// a copy of which can be found in the LICENSE_STDLIB file.
<*
 @require $defined((Key){}.hash()) : `No .hash function found on the key`
*>
module std::collections::cache{Key, Value};

import std::collections::map;

const Allocator MAP_HEAP_ALLOCATOR = (Allocator)&dummy;
const uint DEFAULT_INITIAL_CAPACITY = 16;

alias CacheMap @private = HashMap{ Key, Node* };

struct Node @private
{
	Key   key;
	Value value;
	Node* prev;
	Node* next;
}

fn Node* Node.init(&self, Key key, Value value) @private
{
	*self = { .key = key, .value = value, .prev = null, .next = null };
	return self;
}

Node head @private = (Node){};
Node tail @private = (Node){};

<*
 Implements the LRU cache eviction strategy that drops the least used data if
 capacity is reached. `get` and `set` perform in constant time complexity O(1).
*>
struct LRUCache
{
	CacheMap   map;
	Node*      head;
	Node*      tail;
	Allocator  allocator;
	usz        capacity; // Number of elements
}

<*
 @param [&inout] allocator : "The allocator to use"
 @require capacity > 0 : "The capacity must be 1 or higher"
*>
fn LRUCache* LRUCache.init(&self, Allocator allocator, uint capacity = DEFAULT_INITIAL_CAPACITY)
{
	self.map.init(allocator);

	self.head = &head;
	self.tail = &tail;
	self.head.next = self.tail;
	self.tail.prev = self.head;

	self.allocator = allocator;
	self.capacity = capacity;
	return self;
}

<*
 @require capacity > 0 : "The capacity must be 1 or higher"
*>
fn LRUCache* LRUCache.tinit(&self, uint capacity = DEFAULT_INITIAL_CAPACITY)
{
	return self.init(tmem, capacity) @inline;
}

fn Value? LRUCache.get(&self, Key key) @operator([])
{
	if (try node = self.map.get(key))
	{
		self.remove_node(node);
		self.add_node(node);
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
		case &dummy:
			self.init(mem);
		case null:
			self.tinit();
		default:
			break;
	}

	if (try node = self.map.get(key))
	{
		self.remove_node(node);
		self.map.remove(key);
	}

	if (self.map.len() >= self.capacity)
	{
		Node* lru = self.tail.prev;
		self.remove_node(lru);
		self.map.remove(lru.key);
	}

	Node* new_node = allocator::new(self.allocator, Node);
	new_node.init(key, value);
	self.add_node(new_node);
	self.map.set(key, new_node);
	return true;
}

<*
 Add node at the front of the linked list.
*>
fn void LRUCache.add_node(&self, Node *node) @private
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

int dummy @local;
