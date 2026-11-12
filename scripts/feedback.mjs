import { spawn, spawnSync } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'
import { performance } from 'node:perf_hooks'
import { projectRoot, toolEnvironment } from './harmony-tools.mjs'

const scopeItemPattern = /^[A-Za-z][A-Za-z0-9_.]*(?:#[A-Za-z0-9_.]+)?$/
const testSummaryPattern =
  /Tests run: (\d+), Failure: (\d+), Error: (\d+), Pass: (\d+), Ignore: (\d+)/
/** 单条命令的默认上限；超时后杀掉整个子进程组，避免 hvigor 后代占着管道不返回。 */
const DEFAULT_COMMAND_TIMEOUT_MS = 15 * 60 * 1000
const PIPE_DRAIN_GRACE_MS = 1000
const KILL_WAIT_MS = 5000

export class UsageError extends Error {
  constructor(message, usage) {
    super(`${message}\n用法: ${usage}`)
    this.name = 'UsageError'
  }
}

export function parseRunnerArgs(argv, options) {
  const verbose = argv.includes('--verbose')
  const positional = []

  for (const argument of argv) {
    if (argument === '--verbose') continue
    if (argument.startsWith('-')) {
      throw new UsageError(`未知选项: ${argument}`, options.usage)
    }
    positional.push(argument)
  }

  if (!options.allowScope && positional.length > 0) {
    throw new UsageError(
      options.positionalError ?? '该命令不接受额外参数。',
      options.usage,
    )
  }
  if (options.allowScope && positional.length > 1) {
    throw new UsageError('只接受一个 scope 参数。', options.usage)
  }
  if (positional.length === 1 && positional[0].trim() === '') {
    throw new UsageError('scope 不能为空。', options.usage)
  }

  const scope = positional[0]
  if (scope) {
    const invalidItem = scope
      .split(',')
      .find((item) => !scopeItemPattern.test(item))
    if (invalidItem !== undefined) {
      throw new UsageError(
        `非法 scope: ${scope}。scope 只能使用 Suite 或 Suite#case，并用逗号分隔。`,
        options.usage,
      )
    }
  }

  return { verbose, scope }
}

export async function runCaptured(command, args, options) {
  const logPath = options.logPath
  fs.mkdirSync(path.dirname(logPath), { recursive: true })

  const log = fs.createWriteStream(logPath, { flags: 'w' })
  const startedAt = performance.now()
  const timeoutMs = resolveTimeoutMs(options.timeoutMs)
  let spawnError = null
  let timedOut = false

  const child = spawn(command, args, {
    cwd: options.cwd ?? projectRoot,
    env: options.env ?? toolEnvironment(),
    stdio: ['ignore', 'pipe', 'pipe'],
    shell: process.platform === 'win32',
    // POSIX 下让子进程成为独立进程组，超时时可以连同 hvigor 的后代一起回收。
    detached: process.platform !== 'win32',
  })

  child.stdout.on('data', (chunk) => {
    log.write(chunk)
    if (options.verbose) process.stdout.write(chunk)
  })
  child.stderr.on('data', (chunk) => {
    log.write(chunk)
    if (options.verbose) process.stderr.write(chunk)
  })
  child.once('error', (error) => {
    spawnError = error
    const message = `[无法启动命令: ${error.message}]\n`
    log.write(message)
    if (options.verbose) process.stderr.write(message)
  })

  const { code, signal } = await new Promise((resolve) => {
    let settled = false
    let lastExit = null
    let timeoutHandle = null
    let drainHandle = null

    const finish = (info) => {
      if (settled) return
      settled = true
      if (timeoutHandle !== null) clearTimeout(timeoutHandle)
      if (drainHandle !== null) clearTimeout(drainHandle)
      resolve(info)
    }

    const finishAfterDrain = (info) => {
      if (drainHandle !== null) clearTimeout(drainHandle)
      drainHandle = setTimeout(() => {
        // 正常退出后管道仍不关闭，说明还有后代进程占着 stdout/stderr。
        // 先回收进程组，再结束等待，避免 runCaptured 永久挂起。
        terminateProcessTree(child)
        finish(info)
      }, PIPE_DRAIN_GRACE_MS)
    }

    child.once('exit', (exitCode, exitSignal) => {
      lastExit = { code: exitCode, signal: exitSignal }
      finishAfterDrain(lastExit)
    })
    child.once('close', (exitCode, exitSignal) => {
      lastExit = { code: exitCode, signal: exitSignal }
      finish(lastExit)
    })

    timeoutHandle = setTimeout(() => {
      timedOut = true
      const message = `\n[命令超时: ${formatDuration(timeoutMs)}，已终止子进程组]\n`
      log.write(message)
      if (options.verbose) process.stderr.write(message)
      terminateProcessTree(child)
      if (drainHandle !== null) clearTimeout(drainHandle)
      drainHandle = setTimeout(() => {
        finish(lastExit ?? { code: null, signal: 'SIGKILL' })
      }, KILL_WAIT_MS)
    }, timeoutMs)
  })
  await new Promise((resolve) => log.end(resolve))
  const status = timedOut
    ? 124
    : Number.isInteger(code) && code >= 0
      ? code
      : 1

  return {
    status,
    signal,
    spawnError,
    timedOut,
    elapsedMs: performance.now() - startedAt,
    logPath,
  }
}

function resolveTimeoutMs(configured) {
  const value = Number(configured ?? process.env.WISP_MUSIC_COMMAND_TIMEOUT_MS)
  return Number.isFinite(value) && value > 0
    ? value
    : DEFAULT_COMMAND_TIMEOUT_MS
}

function terminateProcessTree(child) {
  if (child.pid === undefined) return
  if (process.platform === 'win32') {
    spawnSync('taskkill', ['/pid', String(child.pid), '/T', '/F'], {
      stdio: 'ignore',
    })
    return
  }
  try {
    process.kill(-child.pid, 'SIGKILL')
  } catch (_error) {
    try {
      child.kill('SIGKILL')
    } catch (_killError) {
      // 进程已经退出时忽略。
    }
  }
}

export function parseTestResult(content) {
  const summaryMatch = content.match(testSummaryPattern)
  if (!summaryMatch) return null

  const records = []
  let suite = ''
  let current = null
  let pendingDetails = []

  for (const rawLine of content.split(/\r?\n/)) {
    const line = rawLine.trim()
    if (line.startsWith('class=')) {
      const nextSuite = line.slice('class='.length)
      if (nextSuite !== suite) {
        suite = nextSuite
        pendingDetails = []
      }
      continue
    }
    if (line.startsWith('test=')) {
      current = {
        suite,
        test: line.slice('test='.length),
        result: null,
        details: pendingDetails,
      }
      pendingDetails = []
      continue
    }
    if (line.startsWith('result=') && current) {
      current.details.push(...pendingDetails)
      pendingDetails = []
      current.result = line.slice('result='.length)
      records.push(current)
      current = null
      continue
    }
    if (!line || line.startsWith('Tests run:')) continue

    pendingDetails.push(line)
    if (pendingDetails.length > 40) pendingDetails.shift()
  }

  return {
    summary: {
      total: Number(summaryMatch[1]),
      failures: Number(summaryMatch[2]),
      errors: Number(summaryMatch[3]),
      passed: Number(summaryMatch[4]),
      ignored: Number(summaryMatch[5]),
    },
    records,
  }
}

export function findUnmatchedScopes(records, scope) {
  if (!scope) return []

  return scope.split(',').filter((item) => {
    if (item.includes('#')) {
      return !records.some(
        (record) => `${record.suite}#${record.test}` === item,
      )
    }
    return !records.some(
      (record) =>
        record.suite === item || record.suite.startsWith(`${item}.`),
    )
  })
}

export function printTestFailureDetails(parsed) {
  const failures = parsed.records.filter(
    (record) => record.result === 'Failure' || record.result === 'Error',
  )
  const visibleFailures = failures.slice(0, 20)

  for (const failure of visibleFailures) {
    const diagnostic =
      failure.details.find((line) =>
        /Error in|message:|AssertionError|Error:/.test(line),
      ) ?? failure.details[0]
    const suffix = diagnostic ? `: ${truncate(diagnostic, 260)}` : ''
    console.error(
      `  ${failure.suite}#${failure.test} [${failure.result}]${suffix}`,
    )
  }

  if (failures.length > visibleFailures.length) {
    console.error(
      `  其余 ${failures.length - visibleFailures.length} 个失败用例见完整日志。`,
    )
  }
}

export function printLogTail(logPath, maxLines = 40) {
  if (!fs.existsSync(logPath)) return

  const lines = fs
    .readFileSync(logPath, 'utf8')
    .split(/\r?\n/)
    .filter((line) => line.trim())
  if (lines.length === 0) return

  console.error('最近日志:')
  for (const line of lines.slice(-maxLines)) {
    console.error(`  ${truncate(line, 320)}`)
  }
}

export function relativeProjectPath(filePath) {
  return path.relative(projectRoot, filePath)
}

export function formatDuration(elapsedMs) {
  return `${(elapsedMs / 1000).toFixed(2)}s`
}

function truncate(value, maxLength) {
  if (value.length <= maxLength) return value
  return `${value.slice(0, maxLength - 3)}...`
}
