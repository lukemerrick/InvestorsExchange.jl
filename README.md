# IEX
Downloads [tick-by-tick historical trade data from the IEX exchange](https://iextrading.com/trading/market-data/#hist). Specifically, this tool downloads the archived data feed files which IEX uploads daily on a T+1 basis, and supports parsing these files into tabular format. 

Inspired by [this Python implementation](https://github.com/vfrazao-ns1/IEXTools/tree/5f4755f99920dd82c62f050c03b30816342ad519/IEXTools).

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