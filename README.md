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