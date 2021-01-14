import HTTP
import JSON
import Printf
import ProgressMeter
import URIParser


# API for getting URLs for historical data files
const HIST_API_ENDPOINT = "https://api.iextrading.com/1.0/hist"

"""Get all the download links!"""
function query_hist_filenames()
    res = HTTP.get(HIST_API_ENDPOINT)
    payload = JSON.parse(String(res.body))
end

"""Download a file from the internet, with an optional progress bar."""
function download_file(link::String, out_dir::String; chunk_bytes::Int=4096, show_progress_bar::Bool=true)::String
    uri = URIParser.URI(URIParser.unescape(link))
    filename = split(uri.path, '/')[end]
    filepath = joinpath(out_dir, filename)
    HTTP.open("GET", link, readtimeout=10, retries=3) do http
        downloaded_bytes = 0
        response_header = HTTP.startread(http)
        total_bytes = parse(Int, HTTP.header(response_header, "Content-Length"))
        progress_bar = show_progress_bar ? Progress(total_bytes) : nothing
        open(filepath, "w") do io
            while !HTTP.eof(http)
                chunk = HTTP.read(http, chunk_bytes)
                downloaded_bytes += length(chunk)
                write(io, chunk)
                if show_progress_bar
                    downloaded_mb = @Printf.sprintf "%.2f" downloaded_bytes / 2^20
                    progress_values = [("MB", downloaded_mb)]
                    ProgressMeter.update!(
                        progress_bar, downloaded_bytes, showvalues=progress_values
                    )
                end
            end
        end
    end
    return filepath
end
