import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'
import {
  findUnmatchedScopes,
  formatDuration,
  parseRunnerArgs,
  parseTestResult,
  printLogTail,
  printTestFailureDetails,
  relativeProjectPath,
  runCaptured,
} from './feedback.mjs'
import {
  ensureOhpmDependencies,
  projectRoot,
  requireHvigor,
} from './harmony-tools.mjs'
import { relaunchWithoutDeleteGuard } from './guard-shim.mjs'

// 宿主删除守卫的 preload 无法在当前进程卸载；带着它删除 test_result.txt 会被拒绝。
// 检测到注入时先以清理过的环境重启自身，再走正常流程。
const guardStatus = relaunchWithoutDeleteGuard(import.meta.url)
if (guardStatus !== null) process.exit(guardStatus)

const usage = 'npm test [--verbose] [Suite|Suite#case[, ...]]'
const resultPath = path.join(
  projectRoot,
  'entry',
  '.test',
  'default',
  'intermediates',
  'test',
  'coverage_data',
  'test_result.txt',
)
const logPath = path.join(projectRoot, 'entry', '.test', 'logs', 'test.log')
const themeScriptPath = path.join(projectRoot, 'scripts', 'theme.mjs')
const uiIdsScriptPath = path.join(projectRoot, 'scripts', 'ui-ids.mjs')

async function main() {
  let options
  try {
    options = parseRunnerArgs(process.argv.slice(2), {
      allowScope: true,
      usage,
    })
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error))
    process.exitCode = 1
    return
  }

  // 颜色守卫（scripts/theme.mjs --check，规则 0–6）：在任何 hvigor 调用与 test.log 打开之前跑，
  // 守卫输出不会被测试日志截断（规则 doc 见 AGENTS.md「构建与验证」）。
  // 副作用是设计意图：正有人在改 color.json 时，定向跑某个 suite 也会失败。
  const themeGuard = spawnSync(process.execPath, [themeScriptPath, '--check'], {
    cwd: projectRoot,
    encoding: 'utf8',
    timeout: 60_000,
    maxBuffer: 8 * 1024 * 1024,
  })
  if (themeGuard.stdout) process.stdout.write(themeGuard.stdout)
  if (themeGuard.stderr) process.stderr.write(themeGuard.stderr)
  if (themeGuard.error) {
    console.error(`颜色守卫无法运行: ${themeGuard.error.message}`)
    process.exitCode = 1
    return
  }
  if (themeGuard.status !== 0) {
    console.error('颜色守卫失败: 上方为 scripts/theme.mjs --check 的报告（单独诊断: npm run check:theme）')
    process.exitCode = themeGuard.status === null ? 1 : themeGuard.status
    return
  }

  // uitest 选择器守卫（scripts/ui-ids.mjs --check）：生成物必须与 scripts/ui-ids.json 同步，
  // 且代码里引用的 NativeUiIds 成员必须存在。与颜色守卫同样是「先守卫、后 hvigor」。
  const uiIdsGuard = spawnSync(process.execPath, [uiIdsScriptPath, '--check'], {
    cwd: projectRoot,
    encoding: 'utf8',
    timeout: 60_000,
    maxBuffer: 8 * 1024 * 1024,
  })
  if (uiIdsGuard.stdout) process.stdout.write(uiIdsGuard.stdout)
  if (uiIdsGuard.stderr) process.stderr.write(uiIdsGuard.stderr)
  if (uiIdsGuard.error) {
    console.error(`选择器守卫无法运行: ${uiIdsGuard.error.message}`)
    process.exitCode = 1
    return
  }
  if (uiIdsGuard.status !== 0) {
    console.error('选择器守卫失败: 见上方 scripts/ui-ids.mjs --check 的报告（单独诊断: npm run check:ui-ids）')
    process.exitCode = uiIdsGuard.status === null ? 1 : uiIdsGuard.status
    return
  }

  try {
    await ensureOhpmDependencies({
      quiet: true,
      execute: (command, args) =>
        runCaptured(command, args, { logPath, verbose: options.verbose }),
    })

    const hvigor = requireHvigor()
    const hvigorArgs = [
      'test',
      '--mode',
      'module',
      '-p',
      'module=entry@default',
    ]
    if (options.scope) {
      hvigorArgs.push('-p', `scope=${options.scope}`)
    }

    fs.rmSync(resultPath, { force: true })
    const result = await runCaptured(hvigor, hvigorArgs, {
      logPath,
      verbose: options.verbose,
    })

    if (!fs.existsSync(resultPath)) {
      const reason = result.timedOut
        ? `命令超时，已终止子进程组`
        : `未生成结果文件`
      console.error(
        `测试失败: ${reason} (${formatDuration(result.elapsedMs)}); 日志: ${relativeProjectPath(logPath)}`,
      )
      printLogTail(logPath)
      process.exitCode = result.status === 0 ? 1 : result.status
      return
    }

    const parsed = parseTestResult(fs.readFileSync(resultPath, 'utf8'))
    if (!parsed) {
      console.error(
        `测试失败: 无法解析测试汇总 (${formatDuration(result.elapsedMs)}); 日志: ${relativeProjectPath(logPath)}`,
      )
      printLogTail(logPath)
      process.exitCode = result.status === 0 ? 1 : result.status
      return
    }

    const { summary } = parsed
    const unmatched = findUnmatchedScopes(parsed.records, options.scope)
    const failed =
      result.status !== 0 ||
      summary.total === 0 ||
      summary.failures > 0 ||
      summary.errors > 0 ||
      summary.ignored > 0 ||
      unmatched.length > 0

    if (failed) {
      const scopeSuffix = options.scope ? `; scope=${options.scope}` : ''
      console.error(
        `测试失败: ${summary.failures} failed, ${summary.errors} errors, ${summary.passed} passed, ${summary.ignored} ignored (${formatDuration(result.elapsedMs)}${scopeSuffix}); 日志: ${relativeProjectPath(logPath)}`,
      )
      printTestFailureDetails(parsed)
      if (summary.total === 0) {
        console.error('  未执行任何测试，请检查 scope。')
      }
      if (unmatched.length > 0) {
        console.error(`  未匹配 scope: ${unmatched.join(', ')}`)
      }
      if (summary.ignored > 0) {
        console.error(`  ${summary.ignored} 个用例被忽略（ignored），请移除忽略标记或在显式白名单中说明。`)
      }
      if (result.status !== 0) {
        console.error(`  Hvigor 退出码: ${result.status}`)
        if (summary.failures === 0 && summary.errors === 0) {
          printLogTail(logPath)
        }
      }
      process.exitCode = result.status === 0 ? 1 : result.status
      return
    }

    const scopeSuffix = options.scope ? `; scope=${options.scope}` : ''
    console.log(
      `测试通过: ${summary.passed} passed, ${summary.failures} failed, ${summary.errors} errors, ${summary.ignored} ignored (${formatDuration(result.elapsedMs)}${scopeSuffix})`,
    )
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    console.error(`测试失败: ${message}`)
    if (fs.existsSync(logPath)) {
      console.error(`日志: ${relativeProjectPath(logPath)}`)
      printLogTail(logPath)
    }
    process.exitCode = 1
  }
}

await main()
