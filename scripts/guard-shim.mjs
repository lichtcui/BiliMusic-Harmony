// 入口脚本的删除守卫兜底：Node 的 preload 一旦注入就无法在本进程卸载，
// 所以检测到注入时先用清理过的环境重启一次自身，让主流程跑到没有 shim 的进程里。
//
// 这解决的正是「默认环境跑 npm test 必然失败」：npm 启动的 `node scripts/test.mjs`
// 本身带着 shim，会拦掉脚本自己删除 test_result.txt 以及 hvigor 后续的批量清理。
import { spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { hasDeleteGuardInjection, sanitizeBuildEnvironment } from './build-env.mjs'

const REEXEC_MARKER = 'WISP_MUSIC_DELETE_GUARD_REEXEC'

/**
 * 带有删除守卫时重启入口脚本并返回子进程退出码；无需重启时返回 null。
 * 调用方拿到非 null 值后应立即 `process.exit(status)`。
 */
export function relaunchWithoutDeleteGuard(moduleUrl, argv = process.argv.slice(2)) {
  if (process.env[REEXEC_MARKER] === '1') return null
  if (!hasDeleteGuardInjection(process.env)) return null

  const environment = sanitizeBuildEnvironment(process.env)
  environment[REEXEC_MARKER] = '1'
  const result = spawnSync(process.execPath, [fileURLToPath(moduleUrl), ...argv], {
    cwd: process.cwd(),
    env: environment,
    stdio: 'inherit',
  })
  if (result.error) {
    console.error(`重启脚本失败（清理删除守卫后仍无法继续）: ${result.error.message}`)
    return 1
  }
  return result.status ?? 1
}