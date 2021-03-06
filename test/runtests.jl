## -*-Julia-*-
## Test suite for Julia's WAV module
reload("WAV.jl")

# These float array comparison functions are from dists.jl
function absdiff{T<:Real}(current::AbstractArray{T}, target::AbstractArray{T})
    @assert all(size(current) == size(target))
    maximum(abs(current - target))
end

function reldiff{T<:Real}(current::T, target::T)
    abs((current - target)/(bool(target) ? target : 1))
end

function reldiff{T<:Real}(current::AbstractArray{T}, target::AbstractArray{T})
    @assert all(size(current) == size(target))
    maximum([reldiff(current[i], target[i]) for i in 1:numel(target)])
end

## example from README, modified to use an IO buffer
let
    x = [0:7999]
    y = sin(2 * pi * x / 8000)
    io = IOBuffer()
    WAV.wavwrite(y, io, Fs=8000)
    seek(io, 0)
    y, Fs = WAV.wavread(io)
end

## default arguments, GitHub Issue #10
let
    tmp=rand(Float32,(10,2))
    io = IOBuffer()
    WAV.wavwrite(tmp, io; nbits=32)
    seek(io, 0)
    y, fs, nbits, extra = WAV.wavread(io; format="native")
    @assert typeof(y) == Array{Float32, 2}
    @assert fs == 8000.0
    @assert nbits == 32
end

let
    tmp=rand(Float64,(10,2))
    io = IOBuffer()
    WAV.wavwrite(tmp, io; nbits=64)
    seek(io, 0)
    y, fs, nbits, extra = WAV.wavread(io; format="native")
    @assert typeof(y) == Array{Float64, 2}
    @assert fs == 8000.0
    @assert nbits == 64
end

let
    tmp=rand(Float32,(10,2))
    io = IOBuffer()
    WAV.wavwrite(tmp, io; compression=WAV.WAVE_FORMAT_IEEE_FLOAT)
    seek(io, 0)
    y, fs, nbits, extra = WAV.wavread(io; format="native")
    @assert typeof(y) == Array{Float32, 2}
    @assert fs == 8000.0
    @assert nbits == 32
end

## Test wavread and wavwrite
## Generate some wav files for writing and reading
for fs = (8000,11025,22050,44100,48000,96000,192000), nbits = (1,7,8,9,12,16,20,24,32,64), nsamples = convert(Array{Int}, [0, logspace(1, 4, 4)]), nchans = 1:4
    ## Test wav files
    ## The tolerance is based on the number of bits used to encode the file in wavwrite
    tol = 2.0 / (2.0^nbits - 1)

    in_data = rand(nsamples, nchans)
    if nsamples > 0
        @assert maximum(in_data) <= 1.0
        @assert minimum(in_data) >= -1.0
    end
    io = IOBuffer()
    WAV.wavwrite(in_data, io, Fs=fs, nbits=nbits, compression=WAV.WAVE_FORMAT_PCM)
    file_size = position(io)

    ## Check for the common header identifiers
    seek(io, 0)
    @assert read(io, Uint8, 4) == b"RIFF"
    @assert WAV.read_le(io, Uint32) == file_size - 8
    @assert read(io, Uint8, 4) == b"WAVE"

    ## Check that wavread works on the wavwrite produced memory
    seek(io, 0)
    sz = WAV.wavread(io, format="size")
    @assert sz == (nsamples, nchans)

    seek(io, 0)
    out_data, out_fs, out_nbits, out_extra = WAV.wavread(io)
    @assert length(out_data) == nsamples * nchans
    @assert size(out_data, 1) == nsamples
    @assert size(out_data, 2) == nchans
    @assert typeof(out_data) == Array{Float64, 2}
    @assert out_fs == fs
    @assert out_nbits == nbits
    @assert out_extra == None
    if nsamples > 0
        @assert absdiff(out_data, in_data) < tol
    end

    ## test the "subrange" option.
    if nsamples > 0
        seek(io, 0)
        # Don't convert to Int, test if passing a float (nsamples/2) behaves as expected
        subsamples = min(10, int(nsamples / 2))
        out_data, out_fs, out_nbits, out_extra = WAV.wavread(io, subrange=subsamples)
        @assert length(out_data) == subsamples * nchans
        @assert size(out_data, 1) == subsamples
        @assert size(out_data, 2) == nchans
        @assert typeof(out_data) == Array{Float64, 2}
        @assert out_fs == fs
        @assert out_nbits == nbits
        @assert out_extra == None
        @assert absdiff(out_data, in_data[1:int(subsamples), :]) < tol

        seek(io, 0)
        sr = convert(Int, min(5, int(nsamples / 2))):convert(Int, min(23, nsamples - 1))
        out_data, out_fs, out_nbits, out_extra = WAV.wavread(io, subrange=sr)
        @assert length(out_data) == length(sr) * nchans
        @assert size(out_data, 1) == length(sr)
        @assert size(out_data, 2) == nchans
        @assert typeof(out_data) == Array{Float64, 2}
        @assert out_fs == fs
        @assert out_nbits == nbits
        @assert out_extra == None
        @assert absdiff(out_data, in_data[sr, :]) < tol
    end
end

## Test native encoding of 8 bits
for nchans = (1,2,4)
    in_data_8 = uint8(reshape(int(typemin(Uint8):typemax(Uint8)), (int(256 / nchans), nchans)))
    io = IOBuffer()
    WAV.wavwrite(in_data_8, io)

    seek(io, 0)
    out_data_8, fs, nbits, extra = WAV.wavread(io, format="native")
    @assert fs == 8000
    @assert nbits == 8
    @assert extra == None
    @assert in_data_8 == out_data_8
end

## Test native encoding of 16 bits
for nchans = (1,2,4)
    in_data_16 = int16(reshape(int(typemin(Int16):typemax(Int16)), (int(65536 / nchans), nchans)))
    io = IOBuffer()
    WAV.wavwrite(in_data_16, io)

    seek(io, 0)
    out_data_16, fs, nbits, extra = WAV.wavread(io, format="native")
    @assert fs == 8000
    @assert nbits == 16
    @assert extra == None
    @assert in_data_16 == out_data_16
end

## Test native encoding of 24 bits
for nchans = (1,2,4)
    in_data_24 = convert(Array{Int32}, reshape(-63:64, int(128 / nchans), nchans))
    io = IOBuffer()
    WAV.wavwrite(in_data_24, io)

    seek(io, 0)
    out_data_24, fs, nbits, extra = WAV.wavread(io, format="native")
    @assert fs == 8000
    @assert nbits == 24
    @assert extra == None
    @assert in_data_24 == out_data_24
end

## Test encoding 32 bit values
for nchans = (1,2,4)
    in_data_single = convert(Array{Float32}, reshape(linspace(-1.0, 1.0, 128), int(128 / nchans), nchans))
    io = IOBuffer()
    WAV.wavwrite(in_data_single, io)

    seek(io, 0)
    out_data_single, fs, nbits, extra = WAV.wavread(io, format="native")
    @assert fs == 8000
    @assert nbits == 32
    @assert extra == None
    @assert in_data_single == out_data_single
end

## Test encoding 32 bit values outside the valid range
for nchans = (1,2,4)
    nsamps = int(128 / nchans)
    in_data_single = convert(Array{Float32}, reshape(-63:64, nsamps, nchans))
    io = IOBuffer()
    WAV.wavwrite(in_data_single, io)

    seek(io, 0)
    out_data_single, fs, nbits, extra = WAV.wavread(io, format="native")
    @assert fs == 8000
    @assert nbits == 32
    @assert extra == None
    @assert [clamp(in_data_single[i, j], float32(-1), float32(1)) for i = 1:nsamps, j = 1:nchans] == out_data_single
end

### Test A-Law and Mu-Law
for nbits = (8, 16), nsamples = convert(Array{Int}, [0, logspace(1, 4, 4)]), nchans = 1:2, fmt=(WAV.WAVE_FORMAT_ALAW, WAV.WAVE_FORMAT_MULAW)
    const fs = 8000.0
    const tol = 2.0 / (2.0^6)
    in_data = rand(nsamples, nchans)
    if nsamples > 0
        @assert maximum(in_data) <= 1.0
        @assert minimum(in_data) >= -1.0
    end
    io = IOBuffer()
    WAV.wavwrite(in_data, io, Fs=fs, nbits=nbits, compression=fmt)
    file_size = position(io)

    ## Check for the common header identifiers
    seek(io, 0)
    @assert read(io, Uint8, 4) == b"RIFF"
    @assert WAV.read_le(io, Uint32) == file_size - 8
    @assert read(io, Uint8, 4) == b"WAVE"

    ## Check that wavread works on the wavwrite produced memory
    seek(io, 0)
    sz = WAV.wavread(io, format="size")
    @assert sz == (nsamples, nchans)

    seek(io, 0)
    out_data, out_fs, out_nbits, out_extra = WAV.wavread(io)
    @assert length(out_data) == nsamples * nchans
    @assert size(out_data, 1) == nsamples
    @assert size(out_data, 2) == nchans
    @assert typeof(out_data) == Array{Float64, 2}
    @assert out_fs == fs
    @assert out_nbits == 8
    @assert out_extra == None
    if nsamples > 0
        @assert absdiff(out_data, in_data) < tol
    end

    ## test the "subrange" option.
    if nsamples > 0
        seek(io, 0)
        # Don't convert to Int, test if passing a float (nsamples/2) behaves as expected
        subsamples = min(10, int(nsamples / 2))
        out_data, out_fs, out_nbits, out_extra = WAV.wavread(io, subrange=subsamples)
        @assert length(out_data) == subsamples * nchans
        @assert size(out_data, 1) == subsamples
        @assert size(out_data, 2) == nchans
        @assert typeof(out_data) == Array{Float64, 2}
        @assert out_fs == fs
        @assert out_nbits == 8
        @assert out_extra == None
        @assert absdiff(out_data, in_data[1:int(subsamples), :]) < tol

        seek(io, 0)
        sr = convert(Int, min(5, int(nsamples / 2))):convert(Int, min(23, nsamples - 1))
        out_data, out_fs, out_nbits, out_extra = WAV.wavread(io, subrange=sr)
        @assert length(out_data) == length(sr) * nchans
        @assert size(out_data, 1) == length(sr)
        @assert size(out_data, 2) == nchans
        @assert typeof(out_data) == Array{Float64, 2}
        @assert out_fs == fs
        @assert out_nbits == 8
        @assert out_extra == None
        @assert absdiff(out_data, in_data[sr, :]) < tol
    end
end

### Test float formatting
for nbits = (32, 64), nsamples = convert(Array{Int}, [0, logspace(1, 4, 4)]), nchans = 1:2, fmt=(WAV.WAVE_FORMAT_IEEE_FLOAT)
    const fs = 8000.0
    const tol = 1e-6
    in_data = rand(nsamples, nchans)
    if nsamples > 0
        @assert maximum(in_data) <= 1.0
        @assert minimum(in_data) >= -1.0
    end
    io = IOBuffer()
    WAV.wavwrite(in_data, io, Fs=fs, nbits=nbits, compression=fmt)
    file_size = position(io)

    ## Check for the common header identifiers
    seek(io, 0)
    @assert read(io, Uint8, 4) == b"RIFF"
    @assert WAV.read_le(io, Uint32) == file_size - 8
    @assert read(io, Uint8, 4) == b"WAVE"

    ## Check that wavread works on the wavwrite produced memory
    seek(io, 0)
    sz = WAV.wavread(io, format="size")
    @assert sz == (nsamples, nchans)

    seek(io, 0)
    out_data, out_fs, out_nbits, out_extra = WAV.wavread(io)
    @assert length(out_data) == nsamples * nchans
    @assert size(out_data, 1) == nsamples
    @assert size(out_data, 2) == nchans
    @assert typeof(out_data) == Array{Float64, 2}
    @assert out_fs == fs
    @assert out_nbits == nbits
    @assert out_extra == None
    if nsamples > 0
        @assert absdiff(out_data, in_data) < tol
    end

    ## test the "subrange" option.
    if nsamples > 0
        seek(io, 0)
        # Don't convert to Int, test if passing a float (nsamples/2) behaves as expected
        subsamples = min(10, int(nsamples / 2))
        out_data, out_fs, out_nbits, out_extra = WAV.wavread(io, subrange=subsamples)
        @assert length(out_data) == subsamples * nchans
        @assert size(out_data, 1) == subsamples
        @assert size(out_data, 2) == nchans
        @assert typeof(out_data) == Array{Float64, 2}
        @assert out_fs == fs
        @assert out_nbits == nbits
        @assert out_extra == None
        @assert absdiff(out_data, in_data[1:int(subsamples), :]) < tol

        seek(io, 0)
        sr = convert(Int, min(5, int(nsamples / 2))):convert(Int, min(23, nsamples - 1))
        out_data, out_fs, out_nbits, out_extra = WAV.wavread(io, subrange=sr)
        @assert length(out_data) == length(sr) * nchans
        @assert size(out_data, 1) == length(sr)
        @assert size(out_data, 2) == nchans
        @assert typeof(out_data) == Array{Float64, 2}
        @assert out_fs == fs
        @assert out_nbits == nbits
        @assert out_extra == None
        @assert absdiff(out_data, in_data[sr, :]) < tol
    end
end
