"""
Example demonstrating the usage of the IEX package.

Downloads historical TOPS feeds from IEX and extracts trade events to parquet files.

Change the PARQUET_DIR constant to adjust the output file.
"""

import Base: Threads
import IEX
import Logging
import Parquet: write_parquet
import Pkg

# add additional non-IEX dependencies
Pkg.add(["Logging", "Parquet"])

# this is the output directory for parquet files containing the trade messages
#  defaults to "./trade_data" if no argument passed
const PARQUET_DIR = isempty(ARGS) ? "./trade_data" : ARGS[1]

# set up console loggingogging
logger = Logging.ConsoleLogger()
Logging.global_logger(logger)

# define methods for downloading and parsing PCAP files in an efficient, parallelized manner
function rewrite_trades(in_filepath::String, out_filepath::String)::String
    trade_messages = IEX.read_trade_report_messages(in_filepath; show_progress_bar=false)
    rm(in_filepath)
    df = IEX.assemble_trade_report_frame(trade_messages)
    write_parquet(out_filepath, df)
    return out_filepath
end

function async_download(download_links, out_dir, out_filepath_channel)
    for link in download_links
        @Logging.info "Downloading from $link"
        filepath = IEX.download_file(link, out_dir; show_progress_bar=false)
        @Logging.info "Completed download of $filepath"
        push!(out_filepath_channel, filepath)
    end
    # signal the end
    push!(out_filepath_channel, nothing)
end

#### actually kick off the downloading! ####
try mkdir(PARQUET_DIR) catch end

# get list of all TOPS 1.6 download links, filtering out those already downloaded
downloaded_dates = Set(filepath[1:8] for filepath in readdir(PARQUET_DIR))
pay = IEX.query_hist_filenames()
download_links = String[]
dates = sort(collect(keys(pay)); rev=true)
for d in dates
    if d in downloaded_dates
        continue
    end
    for blob in pay[d]
        if blob["feed"] == "TOPS" && blob["version"] == "1.6"
            push!(download_links, blob["link"])
        end
    end
end
@Logging.info "Found $(length(download_links)) un-downloaded days to download."

# Using an async process, download files up to a maximum of K waiting to be processed
dl_filepaths = Channel(2)  # Threads.nthreads() + 2 files on disk in worst case
pcap_dir = joinpath(tempdir(), "tmp_iex_download")
try mkdir(pcap_dir) catch end
@Logging.info "Downloading PCAP files to $pcap_dir"
@async async_download(download_links, pcap_dir, dl_filepaths)

# using threads, read trade data from downloaded files, save trade data, and delete files
@Logging.info "Extracting trades to parquet files in $PARQUET_DIR"
thread_results = []
while true
    in_filepath = take!(dl_filepaths)
    if in_filepath === nothing
        break
    end
    out_filename = splitext(splitext(basename(in_filepath))[1])[1] * ".parquet"
    out_filepath = joinpath(PARQUET_DIR, out_filename)
    @Logging.info("Spawning worker thread to rewrite $in_filepath to $out_filepath")
    res = @Threads.spawn rewrite_trades(in_filepath, out_filepath)
    pushfirst!(thread_results, res)
end
while length(thread_results) > 0
    wait(pop!(thread_results))
end
rm(pcap_dir, recursive=true)
