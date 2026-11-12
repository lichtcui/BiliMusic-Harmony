import path from 'node:path'
import { spawn } from 'node:child_process'
import { parseRunnerArgs } from './feedback.mjs'
import { projectRoot } from './harmony-tools.mjs'
import { relaunchWithoutDeleteGuard } from './guard-shim.mjs'

// 同 test.mjs：带删除守卫启动时先重启一次，三个子步骤都继承清理过的环境。
const guardStatus = relaunchWithoutDeleteGuard(import.meta.url)
if (guardStatus !== null) process.exit(guardStatus)

const usage = 'npm run verify -- [--verbose]'
/** 外部兜底：各步骤自身已有超时，这里防止脚本层自身卡死。 */
const STEP_TIMEOUT_MS = 20 * 60 * 1000

function runScript(script, args) {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, [path.join(projectRoot, 'scripts', script), ...args], {
      cwd: projectRoot,
      env: process.env,
      stdio: 'inherit',
      detached: process.platform !== 'win32',
    })
    let settled = false
    let timer = null
    let killFallback = null
    const finish = (status) => {
      if (settled) return
      settled = true
      if (timer !== null) clearTimeout(timer)
      if (killFallback !== null) clearTimeout(killFallback)
      resolve(status)
    }
    timer = setTimeout(() => {
      console.error(
        `${script} 超过 ${Math.round(STEP_TIMEOUT_MS / 60_000)} 分钟，已终止整个进程组。`,
      )
      if (process.platform !== 'win32' && child.pid !== undefined) {
        try {
          process.kill(-child.pid, 'SIGKILL')
        } catch {
          // 进程组可能已经退出。
        }
      }
      try {
        child.kill('SIGKILL')
      } catch {
        // 进程可能已经退出。
      }
      killFallback = setTimeout(() => finish(1), 5_000)
    }, STEP_TIMEOUT_MS)
    child.once('error', (error) => {
      console.error(`无法启动 ${script}: ${error.message}`)
      finish(1)
    })
    child.once('close', (code) => finish(code ?? 1))
  })
}

async function main() {
  let options
  try {
    options = parseRunnerArgs(process.argv.slice(2), {
      allowScope: false,
      positionalError: 'verify 不接受定向范围，始终执行全量测试和构建。',
      usage,
    })
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error))
    process.exitCode = 1
    return
  }

  const forwardedArgs = options.verbose ? ['--verbose'] : []
  for (const script of ['signing-boundary.mjs', 'test.mjs', 'build.mjs']) {
    const status = await runScript(script, forwardedArgs)
    if (status !== 0) {
      process.exitCode = status
      return
    }
  }
}

await main()
