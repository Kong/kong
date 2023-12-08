const fs = require('fs')
const path = require('path')
const AdmZip = require('adm-zip')

const processTextFile = (fileContent, durations) => {
  const lines = fileContent.split(/\n/)

  for (const line of lines) {
    const [suite, testFile, duration] = line.split(/\s+/)
    const durationInSeconds = parseFloat(duration)

    if (!isNaN(durationInSeconds)) {
      const key = `${suite}:${testFile}`
      durations[key] = [...(durations[key] || []), durationInSeconds]
    }
  }
}

const calculateMedian = (arr) => {
  const sortedArr = arr.sort((a, b) => a - b)
  const middle = Math.floor(sortedArr.length / 2)

  return sortedArr.length % 2 === 0
    ? (sortedArr[middle - 1] + sortedArr[middle]) / 2
    : sortedArr[middle]
}

const combineStatistics = (directoryPath, outputFilePath) => {
  const durations = {}

  const files = fs.readdirSync(directoryPath)
  for (const file of files) {
    if (file.endsWith('.zip')) {
      const filePath = path.join(directoryPath, file)
      const zip = new AdmZip(filePath)
      const fileContent = zip.readAsText(zip.getEntries()[0])
      processTextFile(fileContent, durations)
    }
  }

  const outputStream = fs.createWriteStream(outputFilePath)

  for (const key in durations) {
    const medianDuration = calculateMedian(durations[key])
    const [suite, filename] = key.split(':')
    outputStream.write(`${suite}\t${filename}\t${medianDuration}\n`)
  }

  outputStream.end()
  console.log('Combined output written to', outputFilePath)
}

module.exports = combineStatistics
