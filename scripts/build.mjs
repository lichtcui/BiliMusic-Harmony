import fs from 'node:fs'
import path from 'node:path'
import { spawnSync } from 'node:child_process'
import {
  formatDuration,
  parseRunnerArgs,
  printLogTail,
  relativeProjectPath,
  runCaptured,
} from './feedback.mjs'
import {
  ensureOhpmDependencies,
  projectRoot,
  requireHvigor,
} from './harmony-tools.mjs'
import { relaunchWithoutDeleteGuard } from './guard-shim.mjs'

// 同 test.mjs：带删除守卫启动时先重启一次，避免 hvigor 的清理步骤被拦。
const guardStatus = relaunchWithoutDeleteGuard(import.meta.url)
if (guardStatus !== null) process.exit(guardStatus)

const usage = 'npm run build -- [--verbose]'
const outputDir = path.join(
  projectRoot,
  'entry',
  'build',
  'default',
  'outputs',
  'default',
)
const logPath = path.join(projectRoot, 'entry', '.test', 'logs', 'build.log')
const signingBoundaryPath = path.join(projectRoot, 'scripts', 'signing-boundary.mjs')

function checkSigningBoundary() {
  const result = spawnSync(process.execPath, [signingBoundaryPath], {
    cwd: projectRoot,
    stdio: 'inherit',
    timeout: 120_000,
  })
  if (result.error !== undefined && result.error !== null) {
    console.error(`构建前签名边界检查无法运行: ${result.error.message}`)
    return false
  }
  return result.status === 0
}

/** hvigor 增量构建可能不刷新 HAP；先删旧产物，失败后只接受本次运行生成的文件。 */
function clearPreviousHapOutputs() {
  if (!fs.existsSync(outputDir)) return
  for (const name of fs.readdirSync(outputDir)) {
    if (!name.endsWith('.hap')) continue
    try {
      fs.unlinkSync(path.join(outputDir, name))
    } catch (error) {
      const detail = error instanceof Error ? error.message : String(error)
      console.warn(`无法删除旧 HAP ${name}: ${detail}`)
    }
  }
}

async function main() {
  let options
  try {
    options = parseRunnerArgs(process.argv.slice(2), {
      allowScope: false,
      positionalError: 'build 不接受定向范围或其他位置参数。',
      usage,
    })
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error))
    process.exitCode = 1
    return
  }

  try {
    await ensureOhpmDependencies({
      quiet: true,
      execute: (command, args) =>
        runCaptured(command, args, { logPath, verbose: options.verbose }),
    })

    if (!checkSigningBoundary()) {
      console.error('构建失败: 签名边界检查未通过（见上方报告）。')
      process.exitCode = 1
      return
    }

    const hvigor = requireHvigor()
    clearPreviousHapOutputs()
    const buildStartedAt = Date.now()
    const result = await runCaptured(
      hvigor,
      [
        '--mode',
        'module',
        '-p',
        'module=entry@default',
        'assembleHap',
      ],
      { logPath, verbose: options.verbose },
    )
    if (result.status !== 0) {
      const reason = result.timedOut
        ? '命令超时，已终止子进程组'
        : `Hvigor 退出码 ${result.status}`
      console.error(
        `构建失败: ${reason} (${formatDuration(result.elapsedMs)}); 日志: ${relativeProjectPath(logPath)}`,
      )
      printLogTail(logPath)
      process.exitCode = result.status
      return
    }

    const outputs = fs.existsSync(outputDir)
      ? fs.readdirSync(outputDir)
        .filter((name) => name.endsWith('.hap'))
        .filter((name) => {
          try {
            return fs.statSync(path.join(outputDir, name)).mtimeMs >= buildStartedAt - 2_000
          } catch {
            return false
          }
        })
        .sort()
      : []
    if (outputs.length === 0) {
      console.error(
        `构建失败: 未找到 HAP (${formatDuration(result.elapsedMs)}); 日志: ${relativeProjectPath(logPath)}`,
      )
      printLogTail(logPath)
      process.exitCode = 1
      return
    }

    console.log(
      `构建通过: ${outputs.join(', ')} (${formatDuration(result.elapsedMs)})`,
    )
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    console.error(`构建失败: ${message}`)
    if (fs.existsSync(logPath)) {
      console.error(`日志: ${relativeProjectPath(logPath)}`)
      printLogTail(logPath)
    }
    process.exitCode = 1
  }
}

await main()
