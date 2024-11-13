import argparse
import pprint
from pathlib import Path
import plotly.express as px
from plotly.subplots import make_subplots
import pandas as pd
import textwrap
import json

pprint = pprint.PrettyPrinter(indent=4).pprint

def adjust_fig_tick_y(fig, min_y, max_y, row):
    if max_y - min_y <= 5:
        fig.update_yaxes(range=[min_y*0.9, max_y*1.1], row=row)

def main(args: dict):
    fname = Path(args.file).stem
    output_dir = args.output_dir

    with open(args.file) as f:
        input_json = json.load(f)

    df = pd.DataFrame(input_json["data"])

    pprint(df)

    df["rps_error"] = df["rpss"].apply(max) - df["rpss"].apply(min)
    df["latency_p99_error"] = df["latencies_p99"].apply(
        max) - df["latencies_p99"].apply(min)
    df["latency_p90_error"] = df["latencies_p90"].apply(
        max) - df["latencies_p90"].apply(min)

    suite_sequential = "options" in input_json and \
        "suite_sequential" in input_json["options"] and \
        input_json["options"]["suite_sequential"]

    if suite_sequential:
        # Suite must be int if suite_sequential is True, plotly uses suites as x-axis
        df["suite"] = df["suite"].apply(int)
    else:
        # Wrap long labels as suites are string types
        df["suite"] = df["suite"].apply(
            lambda x: "<br>".join(textwrap.wrap(x, width=40)))

    df.sort_values(by=["version", "suite"], inplace=True)

    xaxis_title = "options" in input_json and \
        "xaxis_title" in input_json["options"] and \
        input_json["options"]["xaxis_title"] or "Test Suites"

    # RPS plot
    fig_rps = px.bar(df, x="suite", y="rps", error_y="rps_error",
                     color="version", barmode="group", title="RPS",
                     labels={"suite": xaxis_title})

    # flatten multiple values of each role into separate rows
    df_p99 = df.explode("latencies_p99")
    df_p90 = df.explode("latencies_p90")

    # P99/90 plot
    fig_p99 = px.box(df_p99, x="suite", y="latencies_p99", color="version",
                     points="all", title="P99 Latency", boxmode="group",
                     labels={"suite": xaxis_title, "latencies_p99": "P99 Latency (ms)"})
    adjust_fig_tick_y(fig_p99, min(df_p99['latencies_p99']), max(df_p99['latencies_p99']), 1)

    fig_p90 = px.box(df_p90, x="suite", y="latencies_p90", color="version",
                     points="all", title="P90 Latency", boxmode="group",
                     labels={"suite": xaxis_title, "latencies_p90": "P90 Latency (ms)"})
    adjust_fig_tick_y(fig_p90, min(df_p90['latencies_p90']), max(df_p90['latencies_p90']), 1)

    # Max latency
    fig_max_latency = px.bar(df, x="suite", y="latency_max", color="version",
                             barmode="group", title="Max Latency",
                             labels={"suite": xaxis_title, "latency_max": "Max Latency (ms)"})

    if suite_sequential:
        # Ordinary Least Square Regression
        fig_p99 = px.scatter(
            df_p99, x="suite", y="latencies_p99", color="version", trendline="ols",
                labels={"suite": xaxis_title, "latencies_p99": "P99 Latency (ms)"},
                title="P99 Latency")
        fig_p90 = px.scatter(
            df_p90, x="suite", y="latencies_p90", color="version", trendline="ols",
                labels={"suite": xaxis_title, "latencies_p90": "P90 Latency (ms)"},
                title="P90 Latency")
        fig_max_latency = px.scatter(
            df, x="suite", y="latency_max", color="version", trendline="ols",
                labels={"suite": xaxis_title, "latency_max": "Max Latency (ms)"},
                title="Max Latency")

    # RPS and P99 plot
    combined = make_subplots(rows=2, cols=1, subplot_titles=[
                             fig_rps.layout.title.text, fig_p99.layout.title.text], vertical_spacing=0.12)
    combined.add_traces(fig_rps.data)
    combined.add_traces(fig_p99.data, rows=[
                        2]*len(fig_p99.data), cols=[1]*len(fig_p99.data))
    combined.update_xaxes(title_text=xaxis_title)
    
    # Adjust y-axis ticks only if tickes are too close
    if not suite_sequential:
        adjust_fig_tick_y(combined, min(df_p99['latencies_p99']), max(df_p99['latencies_p99']), 2)

    combined.update_yaxes(title_text="RPS")
    combined.update_yaxes(title_text="P99 Latency (ms)", row=2)
    combined.update_layout(title_text=fname, boxmode="group")
    combined.write_image(
        Path(output_dir, fname + ".combined.png"), width=1080, height=1080, scale=2)
    combined.write_image(
        Path(output_dir, fname + ".combined.svg"), width=1080, height=1080, scale=2)

    # HTML is seperated and interactive graphs
    with open(Path(output_dir, fname + ".plots.html"), "w") as f:
        f.write("<h1>" + fname + " Report: </h1>")
        f.write(fig_rps.to_html(include_plotlyjs="cdn", full_html=False))
        f.write(fig_p99.to_html(include_plotlyjs=False, full_html=False))
        f.write(fig_p90.to_html(include_plotlyjs=False, full_html=False))
        f.write(fig_max_latency.to_html(
            include_plotlyjs=False, full_html=False))

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("file", help="path of json result file")
    parser.add_argument("-o", "--output-dir", default="",
                        help="whether the suite is sequential")
    args = parser.parse_args()

    main(args)
