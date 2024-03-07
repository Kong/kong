import requests
import csv
import io
import sys
import os


VULN_REPORT_HEADERS = ["NAME", "INSTALLED", "FIXED-IN", "TYPE", "VULNERABILITY", "SEVERITY", "DISTRO"]

def make_github_request(url):
    token = os.getenv('GITHUB_TOKEN')
    if not token:
      print("Please set the GITHUB_TOKEN environment variable to a valid GitHub token.")
      sys.exit(1)
    headers = {
        "Accept": "application/vnd.github+json",
        "Authorization": f"Bearer {token}",
        "X-GitHub-Api-Version": "2022-11-28"
    }
    response = requests.get(url, headers=headers)
    return response

def get_workflow_jobs(run_id, repo):
    url = f"https://api.github.com/repos/{repo}/actions/runs/{run_id}/jobs?per_page=1000"
    response = make_github_request(url)
    jobs_list = response.json()
    if not jobs_list:
      return []

    jobs_data = []
    for job in jobs_list.get("jobs", []):
      if not job.get("name").startswith("Scan Images"):
        continue
      jobs_data.append({'id': job.get("id"), 'name': job.get("name")})
    return jobs_data

def download_github_job_logs(job_id, repo):
    url = f"https://api.github.com/repos/{repo}/actions/jobs/{job_id}/logs"
    response = make_github_request(url)
    if not response:
      return ""
    return response.text

def process_logs(text, distro):
    # The header always includes `VULNERABILITY` amongst other things
    # This can certainly be improved to be more durable
    header = "VULNERABILITY"
    capturing = False
    captured_lines = []

    # distro is "Scan Image - $distro_name"
    # we want to extract the distro name from the header
    distro = distro.split(" - ")[1]

    for line in text.splitlines():
        if header in line:
            # find and store the positions of each keyword in the line
            positions = {h: line.find(h) for h in VULN_REPORT_HEADERS}
            capturing = True
            # jump to the next line and skip the header
            continue

        if capturing:
            # extract values based on the positions
            # start from the first keyword and end at the last keyword
            # strip the values to remove any leading or trailing whitespaces
            values = {
                "NAME": line[positions["NAME"]:positions["INSTALLED"]].strip(),
                "INSTALLED": line[positions["INSTALLED"]:positions["FIXED-IN"]].strip(),
                "FIXED-IN": line[positions["FIXED-IN"]:positions["TYPE"]].strip(),
                "TYPE": line[positions["TYPE"]:positions["VULNERABILITY"]].strip(),
                "VULNERABILITY": line[positions["VULNERABILITY"]:positions["SEVERITY"]].strip(),
                "SEVERITY": line[positions["SEVERITY"]:].strip(),
                "DISTRO": distro
            }
            # when there is no name, it means we have reached the end of the data
            if not values["NAME"]:
                capturing = False
                continue
            captured_lines.append(values)

    return captured_lines


def export_to_csv(data, job_id, write_header):
    # Create a StringIO object to write the CSV data into a string
    csv_string = io.StringIO()
    csv_writer = csv.DictWriter(csv_string, fieldnames=VULN_REPORT_HEADERS)

    # Write the header and the rows
    if write_header:
        csv_writer.writeheader()
    for row in data:
        csv_writer.writerow(row)

    # Reset the file pointer to the beginning
    csv_string.seek(0)

    # Save the CSV string to a file
    csv_filename = f"vulnerability_report_{job_id}.csv"
    with open(csv_filename, "a") as file:
        file.write(csv_string.getvalue())
        print("Wrote csv data to " + csv_filename)

if __name__ == "__main__":
  if len(sys.argv) != 2:
    print("Usage: python main.py <run_id>")
    print("This script downloads and processes Security Scan job logs from GitHub Actions.")
    print("<run_id> is the ID of the GitHub Actions run you want to process.")
    print("The script will download logs for jobs in the 'kong/kong-ee' repository.")
    print("Processed data will be exported to CSV files, one for each job.")
    sys.exit(1)

  run_id = sys.argv[1]
  repo = "kong/kong-ee"
  jobs = get_workflow_jobs(run_id, repo)
  write_header = True
  for job in jobs:
    logs = download_github_job_logs(job.get("id"), repo)
    mapped_data = process_logs(logs, job.get("name"))
    export_to_csv(mapped_data, run_id, write_header)
    # only write the header once
    write_header = False
  print("Done.")
