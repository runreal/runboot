import { $ } from './deps.ts'
import { exec } from './utils.ts'

enum PackageType {
	winget,
	choco,
	zip,
}

interface BasePackageConfig {
	name: string
	type: PackageType
	packageId?: string
	version?: string
	downloadLink?: string
	sha256?: string
	installPath?: string
	isInstalled: () => Promise<boolean>
	check: () => Promise<
		{ installed: boolean; bin: string | undefined; version: string | undefined }
	>
	install: () => Promise<void>
	postInstall: () => Promise<void>
}

interface WingetPackageConfig extends BasePackageConfig {
	packageId: string
	version?: string
}

class WingetPackage implements WingetPackageConfig {
	name: string
	type: PackageType
	packageId: string
	version?: string

	constructor(config: WingetPackageConfig) {
		this.name = config.name
		this.type = PackageType.winget
		this.packageId = config.packageId
		this.version = config.version
	}
	async isInstalled(): Promise<boolean> {
		// no easy way to parse winget output
		// const winget = await $`winget list -e --id ${this.packageId}`.captureCombined();
		const winget = await exec(
			'winget',
			['list', '-e', '--id', this.packageId],
			{ quiet: true },
		)
		if (
			winget.output.includes(
				'No installed package found matching input criteria.',
			)
		) {
			return false
		}
		if (winget.output.includes(this.packageId)) {
			return true
		}
		return false
	}
	async install(): Promise<void> {
		console.log(`[${this.name}] installing...`)
		if (await this.isInstalled()) {
			await this.check()
			return
		}
		await $`winget install -e --id ${this.packageId}`
		await this.postInstall()
	}
	async postInstall(): Promise<void> {
		await this.check()
	}
	async check(): Promise<
		{ installed: boolean; bin: string | undefined; version: string | undefined }
	> {
		console.log(`[${this.name}] checking...`)
		try {
			const installed = await $.commandExists(this.name)
			const bin = await $.which(this.name)
			const version = (await $`${this.name} --version`.text()).trim()
			console.log(`[${this.name}] ${version}`)
			console.log(`[${this.name}] ${bin}`)
			return { installed, bin, version }
		} catch (e) {
			console.log(`[${this.name}] check failed: ${e.message}`)
			return { installed: false, bin: undefined, version: undefined }
		}
	}
}

function createPackage(config: Partial<BasePackageConfig>): BasePackageConfig {
	switch (config.type) {
		case PackageType.winget: {
			const pkg = new WingetPackage(config as WingetPackageConfig)
			if (config.isInstalled) pkg.isInstalled = config.isInstalled.bind(pkg)
			if (config.install) pkg.install = config.install.bind(pkg)
			if (config.postInstall) pkg.postInstall = config.postInstall.bind(pkg)
			if (config.check) pkg.check = config.check.bind(pkg)
			return pkg
		}
		case PackageType.zip:
			throw new Error('Not implemented yet')
		case PackageType.choco:
			throw new Error('Not implemented yet')
		default:
			throw new Error('Unsupported package type')
	}
}

export { createPackage, PackageType }
