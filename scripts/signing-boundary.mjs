import fs from 'node:fs'
import path from 'node:path'
import { pathToFileURL } from 'node:url'
import { execFileSync } from 'node:child_process'
import { projectRoot } from './harmony-tools.mjs'

const SIGNING_CONFIG_FILES = ['build-profile.json5', 'entry/build-profile.json5']
const MATERIAL_PATH =
  /(\.(p12|p7b|p7c|cer|jks|keystore|hap|app|patch|pem|key|crt|csr)$)|(^|\/)(signing|signing-materials)\//
const CONFIG_FIELD = /(?:^|[\s,{])['"]?(certpath|storeFile|keyPassword|storePassword|keyAlias|signAlg)['"]?\s*:/m
const SIGNING_FIELDS = new Set([
  'certpath', 'storeFile', 'keyPassword', 'storePassword', 'keyAlias', 'signAlg'
])
const LOCAL_ABSOLUTE_PATH = /["']\/(Users|home|Volumes)\//

const restoreHint = [
  '本机签名放在仓库外，不要入库：',
  '  npm run signing:apply    # 真机签名构建前应用仓库外 patch（保持未暂存）',
  '  npm run signing:restore  # 构建后还原，提交前必须是还原态',
].join('\n')

function git(args) {
  try {
    return execFileSync('git', args, { cwd: projectRoot, encoding: 'utf8' }).trim()
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error)
    throw new Error(`git ${args.join(' ')} 执行失败，签名边界检查 fail-closed: ${detail}`)
  }
}

function lines(value) {
  return value.split('\n').map((line) => line.trim()).filter(Boolean)
}

/** 解析构建配置用到的 JSON5 子集：注释、单引号、无引号键、尾逗号。 */
export function parseJson5(source) {
  let index = 0
  const length = source.length

  function fail(message) {
    throw new Error(`${message} at offset ${index}`)
  }

  function skip() {
    while (index < length) {
      const char = source[index]
      if (char === ' ' || char === '\t' || char === '\n' || char === '\r' || char === '\uFEFF') {
        index += 1
        continue
      }
      if (char === '/' && source[index + 1] === '/') {
        index += 2
        while (index < length && source[index] !== '\n') {
          index += 1
        }
        continue
      }
      if (char === '/' && source[index + 1] === '*') {
        index += 2
        while (index < length && !(source[index] === '*' && source[index + 1] === '/')) {
          index += 1
        }
        if (index >= length) {
          fail('unterminated block comment')
        }
        index += 2
        continue
      }
      break
    }
  }

  function parseString() {
    const quote = source[index]
    index += 1
    let value = ''
    while (index < length) {
      const char = source[index]
      index += 1
      if (char === quote) {
        return value
      }
      if (char !== '\\') {
        value += char
        continue
      }
      const escaped = source[index]
      index += 1
      if (escaped === 'n') {
        value += '\n'
      } else if (escaped === 'r') {
        value += '\r'
      } else if (escaped === 't') {
        value += '\t'
      } else if (escaped === 'b') {
        value += '\b'
      } else if (escaped === 'f') {
        value += '\f'
      } else if (escaped === 'u') {
        const hex = source.slice(index, index + 4)
        if (!/^[0-9a-fA-F]{4}$/.test(hex)) {
          fail('invalid unicode escape')
        }
        value += String.fromCharCode(parseInt(hex, 16))
        index += 4
      } else {
        value += escaped
      }
    }
    fail('unterminated string')
  }

  function parseNumber() {
    const start = index
    while (index < length && /[0-9a-fA-FxXeE+\-.]/.test(source[index])) {
      index += 1
    }
    const raw = source.slice(start, index)
    const value = raw.toLowerCase().startsWith('0x') ? parseInt(raw, 16) : Number(raw)
    if (!Number.isFinite(value)) {
      fail(`invalid number ${raw}`)
    }
    return value
  }

  function parseObject() {
    index += 1
    const result = {}
    skip()
    if (source[index] === '}') {
      index += 1
      return result
    }
    while (true) {
      skip()
      let key = ''
      if (source[index] === '"' || source[index] === "'") {
        key = parseString()
      } else {
        const start = index
        while (index < length && /[A-Za-z0-9_$]/.test(source[index])) {
          index += 1
        }
        if (start === index) {
          fail('expected object key')
        }
        key = source.slice(start, index)
      }
      skip()
      if (source[index] !== ':') {
        fail('expected colon')
      }
      index += 1
      result[key] = parseValue()
      skip()
      if (source[index] === '}') {
        index += 1
        return result
      }
      if (source[index] !== ',') {
        fail('expected comma or closing brace')
      }
      index += 1
      skip()
      if (source[index] === '}') {
        index += 1
        return result
      }
    }
  }

  function parseArray() {
    index += 1
    const result = []
    skip()
    if (source[index] === ']') {
      index += 1
      return result
    }
    while (true) {
      result.push(parseValue())
      skip()
      if (source[index] === ']') {
        index += 1
        return result
      }
      if (source[index] !== ',') {
        fail('expected comma or closing bracket')
      }
      index += 1
      skip()
      if (source[index] === ']') {
        index += 1
        return result
      }
    }
  }

  function parseValue() {
    skip()
    const char = source[index]
    if (char === '{') {
      return parseObject()
    }
    if (char === '[') {
      return parseArray()
    }
    if (char === '"' || char === "'") {
      return parseString()
    }
    if (char === '-' || char === '+' || char === '.' || (char >= '0' && char <= '9')) {
      return parseNumber()
    }
    if (source.startsWith('true', index)) {
      index += 4
      return true
    }
    if (source.startsWith('false', index)) {
      index += 5
      return false
    }
    if (source.startsWith('null', index)) {
      index += 4
      return null
    }
    fail('unexpected value')
  }

  const parsed = parseValue()
  skip()
  if (index !== length) {
    fail('unexpected trailing content')
  }
  return parsed
}

function signingFieldPaths(value, prefix = '') {
  const paths = []
  if (Array.isArray(value)) {
    value.forEach((item, position) => {
      paths.push(...signingFieldPaths(item, `${prefix}[${position}]`))
    })
    return paths
  }
  if (value !== null && typeof value === 'object') {
    for (const key of Object.keys(value)) {
      const path = prefix.length === 0 ? key : `${prefix}.${key}`
      if (SIGNING_FIELDS.has(key)) {
        paths.push(path)
      }
      paths.push(...signingFieldPaths(value[key], path))
    }
  }
  return paths
}

function checkSigningConfigFile(relativePath, violations) {
  const absolutePath = path.join(projectRoot, relativePath)
  if (!fs.existsSync(absolutePath)) {
    return
  }
  const content = fs.readFileSync(absolutePath, 'utf8')
  let parsed = null
  try {
    parsed = parseJson5(content)
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error)
    violations.push(`${relativePath}: 无法解析，签名边界检查 fail-closed（${detail}）`)
    return
  }
  if (parsed !== null && typeof parsed === 'object') {
    const signingConfigs = parsed?.app?.signingConfigs
    if (Array.isArray(signingConfigs) && signingConfigs.length > 0) {
      violations.push(`${relativePath}: app.signingConfigs 非空（${signingConfigs.length} 项）`)
    }
    const products = parsed?.app?.products
    if (Array.isArray(products)) {
      for (const product of products) {
        if (product !== null && typeof product === 'object' && 'signingConfig' in product) {
          violations.push(`${relativePath}: product ${product.name ?? '<unnamed>'} 绑定了 signingConfig`)
        }
      }
    }
  }
  const signingPaths = signingFieldPaths(parsed)
  if (signingPaths.length > 0) {
    violations.push(`${relativePath}: 含签名材料字段（${signingPaths.join(', ')}）`)
  }
  if (LOCAL_ABSOLUTE_PATH.test(content)) {
    violations.push(`${relativePath}: 含本机绝对路径`)
  }
}

function main() {
  const violations = []

  for (const relativePath of SIGNING_CONFIG_FILES) {
    checkSigningConfigFile(relativePath, violations)
  }

  for (const file of lines(git(['ls-files', '*.json5']))) {
    if (SIGNING_CONFIG_FILES.includes(file)) {
      continue
    }
    const content = fs.readFileSync(path.join(projectRoot, file), 'utf8')
    if (CONFIG_FIELD.test(content)) {
      violations.push(`${file}: 含签名材料字段`)
    }
  }

  for (const file of lines(git(['ls-files']))) {
    if (MATERIAL_PATH.test(file)) {
      violations.push(`${file}: 已跟踪单据/证书/HAP 等签名或构建产物`)
    }
  }

  for (const file of lines(git(['diff', '--cached', '--name-only']))) {
    if (MATERIAL_PATH.test(file)) {
      violations.push(`${file}: 已暂存签名或构建产物`)
    }
  }

  for (const entry of lines(git(['status', '--porcelain']))) {
    const file = entry.replace(/^..\s+/, '').replace(/^"(.*)"$/, '$1')
    if (MATERIAL_PATH.test(file)) {
      violations.push(`${file}: 工作区内存在签名或构建产物`)
    }
  }

  if (violations.length === 0) {
    console.log('签名边界检查通过: signingConfigs 为空、无签名材料入库、无本机绝对路径。')
    return
  }

  console.error('签名边界检查失败:')
  for (const violation of violations) {
    console.error(`  - ${violation}`)
  }
  console.error(restoreHint)
  process.exitCode = 1
}

if (process.argv[1] !== undefined &&
  import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  main()
}