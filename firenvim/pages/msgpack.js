// The msgpack that nvim's RPC needs: encode requests, and decode messages
// from a stream that may split them anywhere.
"use strict";

const utf8 = new TextEncoder();
const fromUtf8 = new TextDecoder();

function encode(value) {
  const out = [];
  const bytes = (...b) => out.push(...b);
  const be = (n, size) => {
    for (let i = size - 1; i >= 0; i--) out.push(Math.floor(n / 2 ** (8 * i)) & 0xff);
  };
  const write = (v) => {
    if (v === null || v === undefined) return bytes(0xc0);
    if (v === false) return bytes(0xc2);
    if (v === true) return bytes(0xc3);
    if (typeof v === "number") {
      if (Number.isInteger(v) && v >= 0 && v < 2 ** 32) {
        if (v < 0x80) return bytes(v);
        if (v < 0x100) return bytes(0xcc, v);
        if (v < 0x10000) return bytes(0xcd), be(v, 2);
        return bytes(0xce), be(v, 4);
      }
      if (Number.isInteger(v) && v < 0 && v >= -(2 ** 31)) {
        if (v >= -32) return bytes(v & 0xff);
        bytes(0xd2);
        return be(v >>> 0, 4);
      }
      const view = new DataView(new ArrayBuffer(8));
      view.setFloat64(0, v);
      return bytes(0xcb, ...new Uint8Array(view.buffer));
    }
    if (typeof v === "string") {
      const s = utf8.encode(v);
      if (s.length < 32) bytes(0xa0 | s.length);
      else if (s.length < 0x100) bytes(0xd9, s.length);
      else if (s.length < 0x10000) bytes(0xda), be(s.length, 2);
      else bytes(0xdb), be(s.length, 4);
      for (const b of s) out.push(b);
      return;
    }
    if (Array.isArray(v)) {
      if (v.length < 16) bytes(0x90 | v.length);
      else if (v.length < 0x10000) bytes(0xdc), be(v.length, 2);
      else bytes(0xdd), be(v.length, 4);
      return v.forEach(write);
    }
    const entries = Object.entries(v);
    if (entries.length < 16) bytes(0x80 | entries.length);
    else bytes(0xde), be(entries.length, 2);
    for (const [k, item] of entries) write(k), write(item);
  };
  write(value);
  return new Uint8Array(out);
}

const INCOMPLETE = Symbol("incomplete");

// Feed it chunks; it calls `onMessage` with each whole value.
class Decoder {
  constructor(onMessage) {
    this.onMessage = onMessage;
    this.buf = new Uint8Array(0);
  }

  push(chunk) {
    const joined = new Uint8Array(this.buf.length + chunk.length);
    joined.set(this.buf);
    joined.set(chunk, this.buf.length);
    this.buf = joined;
    this.view = new DataView(joined.buffer);
    let start = 0;
    for (;;) {
      this.pos = start;
      let value;
      try {
        value = this.read();
      } catch (e) {
        if (e !== INCOMPLETE) throw e;
        break;
      }
      start = this.pos;
      this.onMessage(value);
      if (start >= this.buf.length) break;
    }
    this.buf = this.buf.slice(start);
  }

  take(n) {
    if (this.pos + n > this.buf.length) throw INCOMPLETE;
    const at = this.pos;
    this.pos += n;
    return at;
  }

  uint(n) {
    const at = this.take(n);
    let v = 0;
    for (let i = 0; i < n; i++) v = v * 256 + this.buf[at + i];
    return v;
  }

  str(n) {
    const at = this.take(n);
    return fromUtf8.decode(this.buf.subarray(at, at + n));
  }

  array(n) {
    const out = new Array(n);
    for (let i = 0; i < n; i++) out[i] = this.read();
    return out;
  }

  map(n) {
    const out = {};
    for (let i = 0; i < n; i++) {
      const k = this.read();
      out[k] = this.read();
    }
    return out;
  }

  // nvim's Buffer, Window and Tabpage handles: their number.
  ext(n) {
    this.take(1);
    const at = this.pos;
    const handle = new Decoder(() => {});
    handle.buf = this.buf.subarray(at, at + n);
    handle.view = new DataView(handle.buf.buffer, handle.buf.byteOffset, handle.buf.byteLength);
    handle.pos = 0;
    this.take(n);
    return handle.read();
  }

  read() {
    const t = this.buf[this.take(1)];
    if (t < 0x80) return t;
    if (t < 0x90) return this.map(t & 0x0f);
    if (t < 0xa0) return this.array(t & 0x0f);
    if (t < 0xc0) return this.str(t & 0x1f);
    if (t >= 0xe0) return t - 0x100;
    switch (t) {
      case 0xc0: return null;
      case 0xc2: return false;
      case 0xc3: return true;
      case 0xc4: return this.buf.slice(this.take(this.uint(1)), this.pos);
      case 0xc5: return this.buf.slice(this.take(this.uint(2)), this.pos);
      case 0xc6: return this.buf.slice(this.take(this.uint(4)), this.pos);
      case 0xc7: return this.ext(this.uint(1));
      case 0xc8: return this.ext(this.uint(2));
      case 0xc9: return this.ext(this.uint(4));
      case 0xca: return this.view.getFloat32(this.take(4));
      case 0xcb: return this.view.getFloat64(this.take(8));
      case 0xcc: return this.uint(1);
      case 0xcd: return this.uint(2);
      case 0xce: return this.uint(4);
      case 0xcf: return this.uint(8);
      case 0xd0: return this.view.getInt8(this.take(1));
      case 0xd1: return this.view.getInt16(this.take(2));
      case 0xd2: return this.view.getInt32(this.take(4));
      case 0xd3: return Number(this.view.getBigInt64(this.take(8)));
      case 0xd4: return this.ext(1);
      case 0xd5: return this.ext(2);
      case 0xd6: return this.ext(4);
      case 0xd7: return this.ext(8);
      case 0xd8: return this.ext(16);
      case 0xd9: return this.str(this.uint(1));
      case 0xda: return this.str(this.uint(2));
      case 0xdb: return this.str(this.uint(4));
      case 0xdc: return this.array(this.uint(2));
      case 0xdd: return this.array(this.uint(4));
      case 0xde: return this.map(this.uint(2));
      case 0xdf: return this.map(this.uint(4));
      default: throw new Error(`msgpack: unknown type 0x${t.toString(16)}`);
    }
  }
}

window.msgpack = { encode, Decoder };
