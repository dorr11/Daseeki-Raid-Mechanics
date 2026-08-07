--[[
    Daseeki Raid Mechanics 2.0 — pure min-heap (engine core, wave 1)

    ENGINE SPEC §3.1: "Tasks live in a min-heap keyed on absolute GetTime()
    (insert and delete-min are O(log n); getting the next due task is O(1))."
    ENGINE SPEC §3.2: cancellation is "an O(n) linear sweep that rebuilds the
    heap afterwards".

    This file is DELIBERATELY PURE: no WoW API, no globals, no addon state, no
    time source. It is the layer the headless harness asserts directly (house
    discipline: pure decision layers get rule-per-rule assertions through the
    real code path, not through a mock).

    Ordering is a strict min on `at`, with insertion sequence as the tie-break so
    a batch of simultaneous expiries drains in a DETERMINISTIC order. The spec
    only requires "in heap order"; determinism is ours, and it is what makes the
    drain assertions meaningful.
--]]

local _, Addon = ...

local Heap = {}
Heap.__index = Heap
if Addon then Addon.Heap = Heap end

-- Strict weak ordering. `at` first, insertion sequence second.
local function less(a, b)
    local aa, bb = a.at, b.at
    if aa ~= bb then return aa < bb end
    return (a.seq or 0) < (b.seq or 0)
end

function Heap.New()
    return setmetatable({ n = 0, nextSeq = 0 }, Heap)
end

-- Sift a node already parked at index `n` up to its place. Does NOT touch seq,
-- so it is safe to reuse when rebuilding (rebuild must preserve original order).
local function siftUp(self, n)
    while n > 1 do
        local p = (n - n % 2) / 2
        if less(self[n], self[p]) then
            self[n], self[p] = self[p], self[n]
            n = p
        else
            return
        end
    end
end

local function siftDown(self, i)
    local n = self.n
    while true do
        local l, r, m = i * 2, i * 2 + 1, i
        if l <= n and less(self[l], self[m]) then m = l end
        if r <= n and less(self[r], self[m]) then m = r end
        if m == i then return end
        self[i], self[m] = self[m], self[i]
        i = m
    end
end

-- Insert without assigning a sequence (rebuild path).
local function insert(self, task)
    local n = self.n + 1
    self.n = n
    self[n] = task
    siftUp(self, n)
end

-- Push a NEW task: stamps the insertion sequence, then inserts.
function Heap:Push(task)
    self.nextSeq = self.nextSeq + 1
    task.seq = self.nextSeq
    insert(self, task)
    return task
end

function Heap:Peek()
    return self[1]
end

function Heap:Pop()
    local n = self.n
    if n == 0 then return nil end
    local top = self[1]
    self[1] = self[n]
    self[n] = nil
    self.n = n - 1
    if self.n > 0 then siftDown(self, 1) end
    return top
end

function Heap:Count()
    return self.n
end

-- ENGINE SPEC §3.2 cancellation: linear sweep, then rebuild. `pred(task)` true
-- removes. Removed tasks are appended to `sink` (so the caller can recycle their
-- tables). Returns the number removed. Insertion sequences are PRESERVED, so a
-- cancel never reorders the survivors relative to each other.
function Heap:RemoveWhere(pred, sink)
    local n = self.n
    if n == 0 then return 0 end
    local kept, removed = {}, 0
    for i = 1, n do
        local t = self[i]
        if pred(t) then
            removed = removed + 1
            if sink then sink[#sink + 1] = t end
        else
            kept[#kept + 1] = t
        end
    end
    if removed == 0 then return 0 end
    for i = 1, n do self[i] = nil end
    self.n = 0
    for i = 1, #kept do insert(self, kept[i]) end
    return removed
end

-- Drop everything (the hard-disable path, ENGINE SPEC §9.4 "flushes the scheduler").
function Heap:Clear(sink)
    local n = self.n
    for i = 1, n do
        if sink then sink[#sink + 1] = self[i] end
        self[i] = nil
    end
    self.n = 0
    return n
end

-- Debug/assertion helper: the tasks in due order, without mutating the heap.
function Heap:ToSortedArray()
    local out = {}
    for i = 1, self.n do out[i] = self[i] end
    table.sort(out, less)
    return out
end

return Heap
