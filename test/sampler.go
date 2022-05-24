package main

import (
	crand "crypto/rand"
	"encoding/base64"
	"encoding/binary"
	"math/rand"
)

type TraceID [16]byte

var rngSeed int64

var randSource *rand.Rand
func init() {
	var rngSeed int64
	_ = binary.Read(crand.Reader, binary.LittleEndian, &rngSeed)
	randSource = rand.New(rand.NewSource(rngSeed))
}


func generateTraceID() TraceID {
	tid := TraceID{}
	randSource.Read(tid[:])
	println("base64: ", base64.StdEncoding.EncodeToString(tid[:]))
	println("string: ", string(tid[:]))
	return tid
}


var p = 0.1
var upperBound = uint64(p * (1 << 63))

func acc(traceID TraceID) uint64 {
	bint := binary.BigEndian.Uint64(traceID[0:8])
	println("bint: ", bint)
	return bint >> 1
}

func main() {
	println("upperBound: ", upperBound)
	println("acc: ", acc(generateTraceID()))
}