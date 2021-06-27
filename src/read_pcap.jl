import DataFrames.DataFrame
import GZip
import ProgressMeter

# IEX pcap file intro constants
const IEX_VERSION = 0x01
const IEX_RESERVED = 0x00
const CHANNEL_ID = 0x00000001
const TOPS_PROTOCOL_ID_1_5 = 0x8002
const TOPS_PROTOCOL_ID_1_6 = 0x8003
const DEEP_PROTOCOL_ID_1_0 = 0x8004

# data type for stock tickers
const EightASCIICharBytes = NTuple{8,UInt8}

struct TradeReportMessage
    sale_condition_flags::UInt8
    timestamp::Int64
    symbol::EightASCIICharBytes
    size::UInt32
    price::Int64
    trade_id::Int64
end

# TODO: Parse more message types like QuoteUpdateMessage and TradeBreakMessage
struct QuoteUpdateMessage
    flags::UInt8
    timestamp::Int64
    symbol::EightASCIICharBytes
    bid_size::UInt32
    bid_price::Int64
    ask_price::Int64
    ask_size::UInt32
end
            
struct TradeBreakMessage
    sale_condition_flags::UInt8
    timestamp::Int64
    symbol::EightASCIICharBytes
    size::UInt32
    price::Int64
    trade_id::Int64
end

"""
Header message format, after the version, reserved, protocol, and channel information
(version, reserved bit, protocol, and channel are fixed for a given feed and version)
"""
struct TPHeaderVaryingHalf
    session_id::UInt32
    payload_length::UInt16
    message_count::UInt16
    stream_offset::Int64 
    first_message_sequence_number::Int64
    send_time::Int64
end


struct TradeMessageIter
    pcap_file::AbstractString
    show_progress_bar::Bool
    protocol_magic_bytes::UInt16
end
TradeMessageIter(pcap_file::AbstractString; show_progress_bar::Bool=true, protocol_magic_bytes::UInt16=TOPS_PROTOCOL_ID_1_6) = TradeMessageIter(pcap_file, show_progress_bar, protocol_magic_bytes)

struct TradeMessageIterState
    io::Union{Nothing,IO}
    messages_left::Int
    n_trades::Int
    progress_bar::Union{Nothing,ProgressMeter.ProgressUnknown}
end
TradeMessageIterState() = TradeMessageIterState(nothing, 0, 0, nothing)


function Base.iterate(
    iter::TradeMessageIter,
    state::TradeMessageIterState=TradeMessageIterState()
)::Union{Tuple{TradeReportMessage,TradeMessageIterState},Nothing}
    io = state.io
    if io === nothing
        io = GZip.open(iter.pcap_file, "r")
    end

    n_trades = state.n_trades
    messages_left = state.messages_left
    progress_bar = state.progress_bar
    if iter.show_progress_bar && progress_bar === nothing
        progress_bar = ProgressMeter.ProgressUnknown()
    end

    while !eof(io)
        # seek for next header while no messages left
        while messages_left == 0
            tp_header = seek_header(io, iter.protocol_magic_bytes)
            if tp_header === nothing
                break
            end
            messages_left = tp_header.message_count
        end

        # if seeking got to the end of the file, break out
        if eof(io)
            break
        end

        # read messsage
        message_size = read(io, UInt16)
        message_type = Char(read(io, 1)[1])
        message = nothing
        if message_type == 'T'  # 'T' means TradeReportMessage
            if !(message_size - 1 == sum(sizeof(x) for x in fieldtypes(TradeReportMessage)))
                throw("WTF!")
            end
            message = read_struct(io, TradeReportMessage)
            n_trades += 1
        else
            _ = read(io, message_size - 1)
        end
        messages_left -= 1
        if progress_bar !== nothing
            ProgressMeter.next!(progress_bar, showvalues=[("Trades", n_trades)])
        end
        if message !== nothing
            new_state = TradeMessageIterState(io, messages_left, n_trades, progress_bar)
            return message, new_state
        end
    end
end
Base.IteratorSize(iter::TradeMessageIter) = Base.SizeUnknown()
Base.IteratorEltype(iter::TradeMessageIter) = Base.HasEltype()
Base.eltype(iter::TradeMessageIter) = TradeReportMessage


"""Equivalent of the `read` function but for structs of fixed-size types"""
function read_struct(io::IO, struct_type::Type)
    field_gen = (
        reinterpret(field_type, read(io, sizeof(field_type)))[1]
        for field_type in fieldtypes(struct_type)
    )
    return struct_type(field_gen...)
end

"""
Reads PCAP file contents until header encountered.
Returns the varying portion of the header.
"""
function seek_header(io, protocol_id)::Union{TPHeaderVaryingHalf,Nothing}
    match_bytes = [
        reinterpret(UInt8, [IEX_VERSION]);
        reinterpret(UInt8, [IEX_RESERVED]);
        reinterpret(UInt8, [protocol_id]);
        reinterpret(UInt8, [CHANNEL_ID]);
    ]
    i = 1
    read_bytes = 0
    while !eof(io)
        next_byte = read(io, 1)[1]
        read_bytes += 1
        if next_byte == match_bytes[i]
            i += 1
            # if we match the first part of the header, read and return the second half
            if i == length(match_bytes) + 1
                remaining_header = read_struct(io, TPHeaderVaryingHalf)
                return remaining_header
            end
        else
            i = 1
        end
    end
    # if we hit EOF, return nothing
    return nothing
end


"""Read all TradeReportMessage messages in a PCAP file."""
function read_trade_report_messages(
    gzipped_pcap_filepath::String;
    show_progress_bar::Bool=true,
    protocol_magic_bytes::UInt16=TOPS_PROTOCOL_ID_1_6
)::Vector{TradeReportMessage}
    trade_messages = TradeReportMessage[]
    trade_message_iter = TradeMessageIter(
        gzipped_pcap_filepath;
        show_progress_bar=show_progress_bar,
        protocol_magic_bytes=protocol_magic_bytes
    )
    for message in trade_message_iter
        push!(trade_messages, message)
    end
    return trade_messages
end


"""Convert a list of TradeReportMessage objects into a DataFrame."""
function assemble_trade_report_frame(trade_report_messages::Vector{TradeReportMessage})::DataFrame
    # extract message structs into a columnar format 
    cols = Dict([
        (name, Vector{type}(undef, length(trade_report_messages)))
        for (name, type) in 
        zip(fieldnames(TradeReportMessage),
            fieldtypes(TradeReportMessage))
    ])
    for (i, msg) in enumerate(trade_report_messages)
        for field in fieldnames(typeof(msg))
            cols[field][i] = getfield(msg, field)
        end
    end

    # convert types
    cols[:symbol] = [strip(transcode(String, [x...])) for x in cols[:symbol]]
    cols[:sale_condition_flags] = Int64.(cols[:sale_condition_flags])
    cols[:size] = Int64.(cols[:size])

    # wrap as DataTable
    df = DataFrame(;cols...)
    return df
end
