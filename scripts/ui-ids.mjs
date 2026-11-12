// uitest 选择器真源生成器与防回归守卫（零依赖纯 Node ESM）。
//
//   node scripts/ui-ids.mjs --write   由 scripts/ui-ids.json 生成 NativeUiIds.ets
//   node scripts/ui-ids.mjs --check   校验生成物、成员唯一性与引用完整性
//
// 规范与 scripts/theme.mjs 一致：单一真源 + 守卫规则；改动流程见 docs/architecture.md。
// 生成物是 `entry/src/main/ets/components/native/NativeUiIds.ets`，调用方仍按
// `NativeUiIds.xxx` 访问，不改任何页面代码。

import fs from 'node:fs'
import path from 'node:path'
import { projectRoot } from './harmony-tools.mjs'

const usage = 'node scripts/ui-ids.mjs --write | --check'

const DATA_PATH = path.join(projectRoot, 'scripts', 'ui-ids.json')
const TARGET_PATH = path.join(
  projectRoot,
  'entry',
  'src',
  'main',
  'ets',
  'components',
  'native',
  'NativeUiIds.ets',
)
const SOURCE_ROOTS = [
  path.join(projectRoot, 'entry', 'src', 'main', 'ets'),
  path.join(projectRoot, 'entry', 'src', 'test'),
]
const IDENTIFIER_PATTERN = /^[A-Za-z_$][\w$]*$/
// 只认 `NativeUiIds.<成员>`，避免把注释里的示例当成引用；成员名后必须是 `(`、`.` 或空白/结尾。
const USAGE_PATTERN = /NativeUiIds\.([A-Za-z_$][\w$]*)/g
const DERIVED_PATTERN = /^NativeUiIds\.([A-Za-z_$][\w$]*)\(([^()]*)\)$/
const DERIVED_ARG_PATTERN = /^NativeUiIds\.([A-Za-z_$][\w$]*)$/

function fail(message) {
  console.error(`ui-ids: ${message}`)
  process.exitCode = 1
}

function loadData() {
  return JSON.parse(fs.readFileSync(DATA_PATH, 'utf8'))
}

function validate(data) {
  const errors = []
  const groups = data.groups
  if (!Array.isArray(groups) || groups.length === 0) errors.push('groups 不能为空')
  const groupSet = new Set(groups)
  if (groupSet.size !== groups.length) errors.push('groups 存在重复项')

  const ids = data.ids
  const idNames = new Set()
  const idValues = new Map()
  const byGroup = new Map(groups.map((group) => [group, []]))
  for (const row of ids) {
    const [name, value, group] = row
    if (!Array.isArray(row) || row.length < 3 || row.length > 4) {
      errors.push(`ids 行格式错误: ${JSON.stringify(row)}`)
      continue
    }
    if (!IDENTIFIER_PATTERN.test(name)) errors.push(`非法字段名: ${name}`)
    if (idNames.has(name)) errors.push(`字段名重复: ${name}`)
    idNames.add(name)
    if (typeof value !== 'string' || value.length === 0) errors.push(`${name} 的选择器为空`)
    if (idValues.has(value)) errors.push(`选择器重复: ${value}（${idValues.get(value)} / ${name}）`)
    idValues.set(value, name)
    if (!byGroup.has(group)) {
      errors.push(`${name} 的分组未知: ${group}`)
      continue
    }
    byGroup.get(group).push(name)
  }

  const dynamicNames = new Set()
  for (const row of data.dynamic) {
    const [name, param, paramType, template] = row
    if (!IDENTIFIER_PATTERN.test(name)) errors.push(`非法动态方法名: ${name}`)
    if (dynamicNames.has(name)) errors.push(`动态方法重复: ${name}`)
    dynamicNames.add(name)
    if (!IDENTIFIER_PATTERN.test(param)) errors.push(`${name} 的参数名非法: ${param}`)
    if (paramType !== 'number' && paramType !== 'string') {
      errors.push(`${name} 的参数类型只支持 number / string: ${paramType}`)
    }
    if (typeof template !== 'string' || !template.includes('${')) {
      errors.push(`${name} 的模板必须引用参数: ${template}`)
    }
  }

  for (const group of groups) {
    const derived = data.derived[group]
    if (!Array.isArray(derived)) {
      errors.push(`derived.${group} 必须是数组`)
      continue
    }
    for (const expression of derived) {
      const match = expression.match(DERIVED_PATTERN)
      if (!match) {
        errors.push(`无法解析派生选择器: ${expression}`)
        continue
      }
      if (!dynamicNames.has(match[1])) errors.push(`派生选择器引用了未知动态方法: ${expression}`)
      for (const arg of match[2].split(',').map((part) => part.trim())) {
        if (arg.length === 0) continue
        const argMatch = arg.match(DERIVED_ARG_PATTERN)
        if (argMatch && !idNames.has(argMatch[1])) {
          errors.push(`派生选择器引用了未知 id: ${expression}`)
        }
      }
    }
    if (byGroup.get(group).length + derived.length === 0) {
      errors.push(`选择器组为空: ${group}`)
    }
  }
  return errors
}

function commentLines(note) {
  if (typeof note !== 'string' || note.length === 0) return []
  const lines = note.split('\n')
  if (lines.length === 1) return [`  /** ${lines[0]} */`]
  return ['  /**', ...lines.map((line) => (line.length === 0 ? '   *' : `   * ${line}`)), '   */']
}

function render(data) {
  const byGroup = new Map(data.groups.map((group) => [group, []]))
  for (const [name, , group] of data.ids) byGroup.get(group).push(name)

  const lines = [
    '/**',
    ' * 本文件由 scripts/ui-ids.mjs 生成，请勿手改。',
    ' *',
    ' * 唯一真源是 scripts/ui-ids.json：改 id 或分组后运行',
    ' *   node scripts/ui-ids.mjs --write',
    ' * `npm test` 会先跑 --check，校验生成物、选择器唯一性与代码里的引用完整性。',
    ' */',
    'export class NativeUiIds {',
  ]

  let previousGroup = ''
  for (const row of data.ids) {
    const [name, value, group, note] = row
    if (previousGroup !== '' && group !== previousGroup) lines.push('')
    previousGroup = group
    lines.push(...commentLines(note))
    lines.push(`  static readonly ${name}: string = '${value}';`)
  }

  for (const group of data.groups) {
    const entries = [
      ...byGroup.get(group).map((name) => `NativeUiIds.${name}`),
      ...(data.derived[group] || []),
    ]
    lines.push('')
    lines.push(`  static ${group}Selectors(): string[] {`)
    lines.push('    return [')
    lines.push(entries.map((entry) => `      ${entry}`).join(',\n'))
    lines.push('    ];')
    lines.push('  }')
  }

  for (const row of data.dynamic) {
    const [name, param, paramType, template, note] = row
    lines.push('')
    lines.push(...commentLines(note))
    lines.push(`  static ${name}(${param}: ${paramType}): string {`)
    lines.push(`    return \`${template}\`;`)
    lines.push('  }')
  }

  lines.push('')
  lines.push('  static all(): string[] {')
  const chain = data.groups.map((group) => `NativeUiIds.${group}Selectors()`)
  lines.push(`    return ${chain[0]}`)
  for (const call of chain.slice(1)) lines.push(`      .concat(${call})`)
  lines.push('  }')
  lines.push('}')
  lines.push('')
  return lines.join('\n')
}

function memberNames(data) {
  const names = new Set(data.ids.map((row) => row[0]))
  for (const row of data.dynamic) names.add(row[0])
  names.add('all')
  for (const group of data.groups) names.add(`${group}Selectors`)
  return names
}

function collectFiles(root) {
  const files = []
  const walk = (directory) => {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      const target = path.join(directory, entry.name)
      if (entry.isDirectory()) walk(target)
      else if (/\.(ets|ts)$/.test(entry.name)) files.push(target)
    }
  }
  walk(root)
  return files
}

function checkUsages(data) {
  const names = memberNames(data)
  const errors = []
  for (const root of SOURCE_ROOTS) {
    for (const file of collectFiles(root)) {
      if (path.resolve(file) === path.resolve(TARGET_PATH)) continue
      const content = fs.readFileSync(file, 'utf8')
      for (const match of content.matchAll(USAGE_PATTERN)) {
        if (!names.has(match[1])) {
          errors.push(`${path.relative(projectRoot, file)} 引用了未定义的 NativeUiIds.${match[1]}`)
        }
      }
    }
  }
  return errors
}

function main() {
  const mode = process.argv[2]
  if (mode !== '--write' && mode !== '--check') {
    console.error(usage)
    process.exitCode = 1
    return
  }

  const data = loadData()
  const errors = validate(data)
  if (errors.length > 0) {
    for (const error of errors) fail(error)
    return
  }

  const expected = render(data)
  if (mode === '--write') {
    fs.writeFileSync(TARGET_PATH, expected)
    const relative = path.relative(projectRoot, TARGET_PATH)
    console.log(`ui-ids: 已生成 ${relative}（${data.ids.length} 个 id，${data.groups.length} 组）`)
    return
  }

  let failed = false
  const actual = fs.existsSync(TARGET_PATH) ? fs.readFileSync(TARGET_PATH, 'utf8') : null
  if (actual !== expected) {
    fail(`${path.relative(projectRoot, TARGET_PATH)} 与 scripts/ui-ids.json 不同步，请运行 node scripts/ui-ids.mjs --write`)
    if (actual !== null) {
      const actualLines = actual.split('\n')
      const expectedLines = expected.split('\n')
      const limit = Math.max(actualLines.length, expectedLines.length)
      for (let index = 0; index < limit; index++) {
        if (actualLines[index] !== expectedLines[index]) {
          console.error(`  首个差异在第 ${index + 1} 行`)
          console.error(`  期望: ${expectedLines[index] ?? '<文件结束>'}`)
          console.error(`  实际: ${actualLines[index] ?? '<文件结束>'}`)
          break
        }
      }
    }
    failed = true
  }

  for (const error of checkUsages(data)) {
    fail(error)
    failed = true
  }

  if (!failed) {
    console.log(`ui-ids: 生成物同步，${data.ids.length} 个 id / ${data.groups.length} 组 / ${data.dynamic.length} 个动态 id`)
  }
}

main()