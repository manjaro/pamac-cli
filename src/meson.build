gobject = dependency('gobject-2.0')
gio = dependency('gio-2.0')
gio_unix = dependency('gio-unix-2.0')

libpamac = dependency('pamac', version : '>=11.7')

common_vala_args = ['--pkg=posix', '--vapidir=' + join_paths(meson.source_root(), 'vapi')]
common_c_args = ['-DGETTEXT_PACKAGE="pamac"']

executable('pamac',
	sources: ['version.vala', 'transaction-cli.vala', 'cli.vala'],
	dependencies: [gio, libpamac],
	vala_args: [common_vala_args, '--pkg=linux'],
	c_args: common_c_args,
	install: true)
