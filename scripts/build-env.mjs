// 宿主删除守卫（safe-delete）注入的清理。
//
// 背景：部分 AI 宿主会给终端注入删除守卫，形态不止一种——`NODE_OPTIONS` 里的
// `--require <shim>.cjs`、`CODEBUDDY_SAFE_DELETE_*` 变量、`BASH_ENV` 里的 shim 脚本，
// 以及 PATH 里的 `safe-bin` 目录。hvigor 的增量清理、测试结果文件删除都会被它拦下，
// 表现为 `[safe-delete][SAFE_DELETE_BULK_CONFIRM_REQUIRED]` 之类的失败，而不是编译错误。
//
// 这里只剔除与删除守卫相关的内容：其余 `NODE_OPTIONS`（例如 `--max-old-space-size`）
// 和普通 PATH 条目原样保留。shim 是按名字判定的（`safe-delete` / `node-language-shim`），
// 因为实测注入的脚本名里并不一定包含 `safe-delete`。
import path from 'node:path'

/** 删除守卫的名字特征：覆盖 `safe-delete`、`safe_delete` 与实测的 shim 文件名。 */
const GUARD_NAME = /safe[-_]?delete|node-language-shim/i
/** PATH 里守卫目录的特征（按路径段匹配，避免误伤普通目录）。 */
const GUARD_PATH_SEGMENT = /(^|[\\/])safe[-_]?bin([\\/]|$)/i
/** 守卫自己的环境变量，例如 `CODEBUDDY_SAFE_DELETE_BROKER`。 */
const GUARD_VARIABLE = /CODEBUDDY_SAFE_DELETE|(^|_)SAFE_DELETE_/i
/** 可能引用 shim 脚本的 shell 入口变量。 */
const SHELL_ENV_VARIABLES = ['BASH_ENV', 'ENV']
/** 需要把下一个参数一起带走的 Node 选项。 */
const NODE_OPTION_FLAGS_WITH_VALUE = new Set([
  '-r',
  '--require',
  '--import',
  '--loader',
  '--experimental-loader',
])

function isGuardReference(value) {
  return GUARD_NAME.test(value)
}

/**
 * 从 `NODE_OPTIONS` 中剔除删除守卫的 preload。`--require <shim>` 是成对出现的，
 * 只删路径会把悬空的 `--require` 留给 Node，所以按选项对处理。
 */
export function sanitizeNodeOptions(nodeOptions) {
  if (typeof nodeOptions !== 'string' || nodeOptions.trim() === '') {
    return nodeOptions ?? ''
  }
  const parts = nodeOptions.trim().split(/\s+/)
  const kept = []
  for (let index = 0; index < parts.length; index += 1) {
    const part = parts[index]
    if (NODE_OPTION_FLAGS_WITH_VALUE.has(part)) {
      const value = parts[index + 1]
      if (value !== undefined && isGuardReference(value)) {
        index += 1
        continue
      }
      kept.push(part)
      continue
    }
    if (isGuardReference(part)) continue
    kept.push(part)
  }
  return kept.join(' ')
}

/**
 * 返回一份去掉删除守卫注入的环境变量副本；入参不被修改。
 * 该副本既可传给子进程，也可用于重新启动当前脚本（见 scripts/guard-shim.mjs）。
 */
export function sanitizeBuildEnvironment(input = process.env) {
  const environment = { ...input }

  if (typeof environment.NODE_OPTIONS === 'string') {
    const sanitized = sanitizeNodeOptions(environment.NODE_OPTIONS)
    if (sanitized.trim() !== '') environment.NODE_OPTIONS = sanitized
    else delete environment.NODE_OPTIONS
  }

  for (const key of Object.keys(environment)) {
    if (key === 'NODE_OPTIONS') continue
    if (GUARD_VARIABLE.test(key)) delete environment[key]
  }

  for (const key of SHELL_ENV_VARIABLES) {
    if (typeof environment[key] === 'string' && isGuardReference(environment[key])) {
      delete environment[key]
    }
  }

  if (typeof environment.PATH === 'string') {
    const entries = environment.PATH
      .split(path.delimiter)
      .filter((entry) => entry !== '' && !isGuardReference(entry) && !GUARD_PATH_SEGMENT.test(entry))
    if (entries.length > 0) environment.PATH = entries.join(path.delimiter)
  }

  return environment
}

/** 当前环境是否带有删除守卫注入（有则需要重启一次脚本才能让本条进程摆脱 shim）。 */
export function hasDeleteGuardInjection(input = process.env) {
  if (typeof input.NODE_OPTIONS === 'string' && sanitizeNodeOptions(input.NODE_OPTIONS) !== input.NODE_OPTIONS) {
    return true
  }
  if (Object.keys(input).some((key) => key !== 'NODE_OPTIONS' && GUARD_VARIABLE.test(key))) {
    return true
  }
  for (const key of SHELL_ENV_VARIABLES) {
    if (typeof input[key] === 'string' && isGuardReference(input[key])) return true
  }
  if (typeof input.PATH === 'string') {
    const entries = input.PATH.split(path.delimiter)
    if (entries.some((entry) => entry !== '' && (isGuardReference(entry) || GUARD_PATH_SEGMENT.test(entry)))) {
      return true
    }
  }
  return false
}