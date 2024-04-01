import { $, mergeReadableStreams } from './deps.ts'

interface WingetPackagesSchema {
	WinGetVersion?: string
	CreationDate?: string
	Sources: {
		SourceDetails: {
			Name: string
			Identifier: string
			Argument: string
			Type: string
		}
		Packages: {
			PackageIdentifier: string
			Version: string
			Channel?: string
			Scope?: 'user' | 'machine'
		}[]
	}[]
}

export interface ExecResult {
	success: boolean
	code: number
	signal: Deno.Signal | null
	output: string
}

let powershell: string | undefined
let wingetExport: WingetPackagesSchema | undefined

export async function fileExists(path: string): Promise<boolean> {
	try {
		const result = await Deno.stat(path)
		return result.isFile
	} catch (err) {
		if (err instanceof Deno.errors.PermissionDenied) {
			throw err
		}
		return false
	}
}

export async function execPowerShell(
	cmd: string,
): Promise<{ status: Deno.ProcessStatus; output: string }> {
	const flags = ['-NoProfile', '-NonInteractive', '-NoLogo']
	const run = [whichPowerShell(), ...flags, '-Command', `${cmd}`]
	const p = Deno.run({ cmd: run, stdout: 'piped' })
	return {
		status: await p.status(),
		output: new TextDecoder().decode(await p.output()).trim(),
	}
}

export function whichPowerShell(): string {
	if (powershell === undefined) {
		const whichPowerShell = $.whichSync('powershell')
		if (whichPowerShell) {
			powershell = whichPowerShell
		}
		const whichPwsh = $.whichSync('pwsh')
		if (whichPwsh) {
			powershell = whichPwsh
		}
	}
	if (powershell === undefined) {
		throw new Error('PowerShell not found')
	}
	return powershell
}

export async function getUserPath(): Promise<string> {
	const { output } = await execPowerShell(
		`[Environment]::GetEnvironmentVariable('PATH', 'User')`,
	)
	return output
}

export async function addUserPathVariable(path: string): Promise<void> {
	const { output: userPath } = await execPowerShell(
		`[Environment]::GetEnvironmentVariable('PATH', 'User')`,
	)
	const userPaths = userPath.split(';')
	if (userPaths.includes(`${path}`)) {
		return
	}
	await execPowerShell(
		`[Environment]::SetEnvironmentVariable('PATH', '${userPath}${path};', 'User')`,
	)
}

export async function detectOSVersion(): Promise<string> {
	const { output } = await execPowerShell(`[Environment]::OSVersion.Version`)
	return output
}

export async function detectWindowsServer(): Promise<boolean> {
	const { output } = await execPowerShell(`(Get-ComputerInfo).OsProductType`)
	return output === 'Server'
}

export async function detectWindowsDesktop(): Promise<boolean> {
	const { output } = await execPowerShell(`(Get-ComputerInfo).OsProductType`)
	return output === 'WorkStation'
}

export async function isWingetInstalled(): Promise<
	{ isInstalled: boolean; version: string }
> {
	const output = await execSync('winget', ['--version'], { quiet: true })
	return { isInstalled: output.success, version: output.output }
}

export async function exec(
	cmd: string,
	args: string[],
	options?: Deno.CommandOptions & { dryRun?: boolean; quiet?: boolean },
): Promise<ExecResult> {
	const { dryRun, quiet, ...denoOptions } = options ||
		{ dryRun: false, quiet: true }

	if (dryRun) {
		console.log(`[${cmd}] ${args.join(' ')}`)
		return { success: true, code: 0, signal: null, output: '' }
	}

	const command = new Deno.Command(cmd, {
		...denoOptions,
		args,
		stderr: 'piped',
		stdout: 'piped',
	})
	const process = command.spawn()
	const joined = mergeReadableStreams(process.stdout, process.stderr)
	let output = ''

	for await (const chunk of joined) {
		if (!quiet) {
			Deno.stdout.write(chunk)
		}
		output += new TextDecoder().decode(chunk)
	}

	output = output.trim()

	const { success, code, signal } = await process.status
	return { success, code, signal, output }
}

export function execSync(
	cmd: string,
	args: string[],
	options?: Deno.CommandOptions & { dryRun?: boolean; quiet?: boolean },
): ExecResult {
	const { dryRun, quiet, ...denoOptions } = options ||
		{ dryRun: false, quiet: true }

	if (dryRun) {
		console.log(`[${cmd}] ${args.join(' ')}`)
		return { success: true, code: 0, signal: null, output: '' }
	}

	const command = new Deno.Command(cmd, {
		...denoOptions,
		args,
		stderr: 'piped',
		stdout: 'piped',
	})
	const process = command.outputSync()
	let output = ''
	if (!quiet) {
		Deno.stdout.writeSync(process.stdout)
		Deno.stderr.writeSync(process.stderr)
	}
	output += new TextDecoder().decode(process.stdout)
	output += new TextDecoder().decode(process.stderr)
	output = output.trim()

	const { success, code, signal } = process
	return { success, code, signal, output }
}

export async function getWingetExportData(): Promise<WingetPackagesSchema> {
	if (wingetExport) {
		return wingetExport
	}
	try {
		const tmpFile = await Deno.makeTempFile()
		await exec('winget', ['export', '-o', tmpFile, '--include-versions'])
		const data = await Deno.readTextFile(tmpFile)
		const json = JSON.parse(data)
		wingetExport = json as WingetPackagesSchema
		return json as WingetPackagesSchema
	} catch (e) {
		console.error(e)
		throw e
	}
}

export async function getWingetExportPackages(): Promise<
	WingetPackagesSchema['Sources'][0]['Packages']
> {
	const data = await getWingetExportData()
	return data.Sources[0].Packages
}
