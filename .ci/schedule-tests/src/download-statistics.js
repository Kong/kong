const fs = require('fs')
const path = require('path')
const { Octokit } = require('@octokit/rest')
const { subDays, format } = require('date-fns')

const token = process.env.GITHUB_TOKEN

const octokit = new Octokit({
  auth: token,
})

const getWorkflowRuns = async (owner, repo, workflowName) => {
  const sevenDaysAgo = format(subDays(new Date(), 1), 'yyyy-MM-dd')

  const response = await octokit.actions.listWorkflowRuns({
    owner,
    repo,
    workflow_id: workflowName,
    per_page: 100,
  })

  return response.data.workflow_runs.filter(
    (run) => run.created_at >= sevenDaysAgo
  )
}

const downloadArtifact = async (
  owner,
  repo,
  runId,
  artifact,
  dataDirectory
) => {
  const response = await octokit.actions.downloadArtifact({
    owner,
    repo,
    artifact_id: artifact.id,
    archive_format: 'zip',
  })

  const filePath = path.join(dataDirectory, `run_${runId}_${artifact.name}.zip`)
  fs.writeFileSync(filePath, Buffer.from(response.data))
  console.log(`Downloaded: ${filePath}`)
}

const shouldDownloadArtifact = (artifact) =>
  artifact.name.match(/^test-runtime-statistics-\d+$/)

const downloadStatistics = async (owner, repo, workflowName, dataDirectory) => {
  try {
    if (!fs.existsSync(dataDirectory)) {
      fs.mkdirSync(dataDirectory)
    }

    const workflowRuns = await getWorkflowRuns(owner, repo, workflowName)

    for (const run of workflowRuns) {
      const artifacts = await octokit.actions.listWorkflowRunArtifacts({
        owner,
        repo,
        run_id: run.id,
      })

      for (const artifact of artifacts.data.artifacts) {
        if (shouldDownloadArtifact(artifact)) {
          await downloadArtifact(owner, repo, run.id, artifact, dataDirectory)
        }
      }
    }
  } catch (error) {
    console.error('Error:', error.message)
  }
}

module.exports = downloadStatistics
