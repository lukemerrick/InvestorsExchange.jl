# InvestorsExchange.jl

Downloads [tick-by-tick historical trade data from the Investors Exchange (IEX)](https://iextrading.com/trading/market-data/#hist). Specifically, this tool downloads the archived data feed files which IEX uploads daily on a T+1 basis, and supports parsing these files into tabular format.

Inspired by [this Python implementation](https://github.com/vfrazao-ns1/IEXTools/).

## Features

### General Features

* Extract trade data to DataFrames files using [DataFrames.jl](https://github.com/JuliaData/DataFrames.jl)
* Download progress bar using [ProgressMeter.jl](https://github.com/timholy/ProgressMeter.jl/)

### TOPS Feed

* TradeReportMessage message type only
* Tested only on version 1.6

### DEEP Feed

* TradeReportMessage message type only
* Untested

## Usage

The package is still in early shape, but I've included the trade download script this package is built to power to show a usage example. You can run this script like this:

```bash
julia --threads <number of CPU cores on your machine> trade_download_script.jl /path/to/save_dir
```

If you don't care about taking advantage of multi-threading or specifying a custom save directory (the default is `./trade_data`), you can just run `julia trade_download_script.jl`.

### Download script details

In the download script, I avoid downloading more than a handful of raw PCAP data files to disk by running downloads [asynchronously](https://docs.julialang.org/en/v1/manual/asynchronous-programming/) with downloaded filenames piped into a limited-sized [Channel](https://docs.julialang.org/en/v1/base/parallel/#Base.Channel). As downloads complete, the file paths are consumed by [multi-threaded](https://docs.julialang.org/en/v1/manual/multi-threading/) parsing code that reads the `TradeReportMessage` messages, organizes them into a Julia `DataTable`, and writes them to disk in parquet format. To take advantage of this parallelization and speed up the parsing of literally every TOPS feed message that IEX has issued since mid 2017, it is recommended you include the `--threads` flag.

### A note on TOPS vs. DEEP

As of v0.1.1, this package only parses the trade report messages in any feed it reads. If you want to read from the DEEP feed or the TOPS v1.5 feed, you'll need to overwrite the default value of the `protocol_magic_bytes` argument in the `read_trade_report_messages` function.

**Example**
```julia
import InvestorsExchange as IEX

IEX.read_trade_report_messages("/tmp/20210420_IEXTP1_DEEP1.0.pcap.gz"; protocol_magic_bytes=IEX.DEEP_PROTOCOL_ID_1_0)
```

However, since TOPS and DEEP both contain the trade report messages, there is little reason to use DEEP (which tends to be bigger) to parse the trade report messages. You should expect faster download and parse speeds with TOPS, and thus it's recommended to stick with TOPS.

