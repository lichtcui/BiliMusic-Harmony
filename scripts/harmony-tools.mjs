import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { sanitizeBuildEnvironment } from './build-env.mjs'

const scriptDir = path.dirname(fileURLToPath(import.meta.url))

export const projectRoot = path.resolve(scriptDir, '..')

const MIN_NODE = [20, 19, 0]
function assertNodeRuntime() {
  const parts = process.versions.node.split('.').map((part) => Number.parseInt(part, 10))
  for (let index = 0; index < MIN_NODE.length; index += 1) {
    const current = Number.isFinite(parts[index]) ? parts[index] : 0
    if (current > MIN_NODE[index]) return
    if (current < MIN_NODE[index]) {
      console.error(`需要 Node >= ${MIN_NODE.join('.')}，当前 ${process.versions.node}。`)
      process.exit(1)
    }
  }
}
assertNodeRuntime()

const DEVECO_ROOT = '/Applications/DevEco-Studio.app/Contents'
export const DEFAULT_DEVECO_SDK_HOME = path.join(DEVECO_ROOT, 'sdk')
export const DEFAULT_HVIGOR =
  path.join(DEVECO_ROOT, 'tools', 'hvigor', 'bin', 'hvigorw')
export const DEFAULT_OHPM =
  path.join(DEVECO_ROOT, 'tools', 'ohpm', 'bin', 'ohpm')

export function commandExists(command) {
  const checker = process.platform === 'win32' ? 'where' : 'which'
  return spawnSync(checker, [command], {
    stdio: 'ignore',
    shell: process.platform === 'win32',
  }).status === 0
}

export function isAvailable(command) {
  return commandExists(command) || fs.existsSync(command)
}

export function firstAvailable(candidates) {
  for (const candidate of candidates) {
    if (candidate && isAvailable(candidate)) return candidate
  }
  return null
}

// 默认入口是 --no-daemon 包装器：Hvigor 守护进程被同机其它工程占用时，客户端会长时间停在
// `Starting hvigor daemon` 而不是回退 no-daemon（见 scripts/hvigorw-no-daemon.mjs）。
// 设置 HVIGOR_BIN 可绕开包装器，直接指定 hvigorw。
export const NO_DAEMON_HVIGOR = path.join(scriptDir, 'hvigorw-no-daemon.mjs')

function isExecutableFile(candidate) {
  try {
    return (fs.statSync(candidate).mode & 0o111) !== 0
  } catch {
    return false
  }
}

export function findHvigor() {
  if (process.env.HVIGOR_BIN) {
    return requireExplicitPath('HVIGOR_BIN', process.env.HVIGOR_BIN)
  }
  return firstAvailable([
    isExecutableFile(NO_DAEMON_HVIGOR) ? NO_DAEMON_HVIGOR : null,
    path.join(projectRoot, 'hvigorw'),
    'hvigorw',
    DEFAULT_HVIGOR,
    'hvigor',
  ])
}

export function findOhpm() {
  if (process.env.OHPM_BIN) {
    return requireExplicitPath('OHPM_BIN', process.env.OHPM_BIN)
  }
  return firstAvailable([
    'ohpm',
    DEFAULT_OHPM,
  ])
}

/** 显式指定的工具路径不可用时应立刻失败，不能静默回退到默认工具链。 */
function requireExplicitPath(name, value) {
  if (!isAvailable(value)) {
    throw new Error(`${name} 指向不可用的路径: ${value}；请修正该环境变量或取消设置。`)
  }
  return value
}

export function run(command, args, options = {}) {
  return spawnSync(command, args, {
    cwd: options.cwd ?? projectRoot,
    env: options.env ?? toolEnvironment(),
    stdio: options.stdio ?? 'inherit',
    shell: process.platform === 'win32',
  })
}

export function toolEnvironment() {
  // 子进程（ohpm / hvigor / 测试）不能继承宿主删除守卫的注入，否则批量清理会被拦下。
  const env = sanitizeBuildEnvironment(process.env)
  if (env.DEVECO_SDK_HOME) {
    if (!fs.existsSync(env.DEVECO_SDK_HOME)) {
      throw new Error(`DEVECO_SDK_HOME 指向不存在的目录: ${env.DEVECO_SDK_HOME}`)
    }
  } else if (fs.existsSync(DEFAULT_DEVECO_SDK_HOME)) {
    env.DEVECO_SDK_HOME = DEFAULT_DEVECO_SDK_HOME
  }
  return env
}

export async function ensureOhpmDependencies(options = {}) {
  const hypiumPath = path.join(projectRoot, 'oh_modules', '@ohos', 'hypium')
  if (fs.existsSync(hypiumPath)) return

  const ohpm = findOhpm()
  if (!ohpm) {
    throw new Error(
      '缺少 HarmonyOS 测试依赖。请设置 OHPM_BIN，或把 ohpm 加入 PATH。',
    )
  }

  if (!options.quiet) console.log(`安装 HarmonyOS 依赖: ${ohpm}`)
  const execute = options.execute ?? run
  const result = await execute(ohpm, [
    'install',
    '--all',
    '--lockfile_stable_order',
    '--auto_skip_install',
  ])
  if (result.status !== 0) {
    throw new Error(`ohpm install 失败，退出码 ${result.status ?? 'unknown'}`)
  }
  if (!fs.existsSync(hypiumPath)) {
    throw new Error(`ohpm install 后仍缺少依赖: ${hypiumPath}`)
  }
}

export function requireHvigor() {
  const hvigor = findHvigor()
  if (!hvigor) {
    throw new Error(
      '未找到 Hvigor。请设置 HVIGOR_BIN，或把 hvigorw 加入 PATH。',
    )
  }
  return hvigor
}
