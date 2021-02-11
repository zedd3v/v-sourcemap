module base64vlq

import io

type DecodeMap = [256]byte

const encode_std = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

const (
	vlq_base_shift       = 5
	vlq_base             = 1 << vlq_base_shift
	vlq_base_mask        = vlq_base - 1
	vlq_sign_bit         = 1
	vlq_continuation_bit = vlq_base
)

const (
	decode_map = DecodeMap([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 62, 0, 0, 0, 63, 52, 53, 54,
		55, 56, 57, 58, 59, 60, 61, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11,
		12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 0, 0, 0, 0, 0, 0, 26, 27, 28, 29,
		30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
)

fn to_vlq_signed(n int) int {
	if n < 0 {
		return -n << 1 + 1
	}
	return n << 1
}

fn from_vlq_signed(n int) int {
	isNeg := n & vlqSignBit != 0
	n >>= 1
	if isNeg {
		return -n
	}
	return n
}

struct Encoder {
	w io.ReaderWriterImpl
}

pub fn new_encoder(w io.ReaderWriterImpl) &Encoder {
	return &Encoder{
		w: w
	}
}

pub fn (enc Encoder) encode(n int32) ? {
	n = to_vlq_signed(n)
	for digit := int32(base64vlq.vlq_continuation_bit); digit & base64vlq.vlq_continuation_bit != 0; {
		digit = n & base64vlq.vlq_base_mask
		n >>= base64vlq.vlq_base_shift
		if n > 0 {
			digit |= base64vlq.vlq_continuation_bit
		}

		enc.w.WriteByte(encodeStd[digit]) ?
	}
	return
}

struct Decoder {
	r io.ReaderWriterImpl
}

pub fn new_decoder(r io.ReaderWriterImpl) Decoder {
	return Decoder{
		r: r
	}
}

pub fn (dec Decoder) decode() ?int {
	shift := byte(0)
	for continuation := true; continuation; {
		c := dec.r.ReadByte() ?
		c = decodeMap[c]
		continuation = c & base64vlq.vlq_continuation_bit != 0
		n += int32(c & base64vlq.vlq_base_mask) << shift
		shift += base64vlq.vlq_base_shift
	}
	return from_vlq_signed(n)
}
