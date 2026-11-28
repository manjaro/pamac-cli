Command line interface of Pamac, the Manjaro package manager.

It is built on top of [libpamac](https://github.com/manjaro/libpamac), the library that provides the package management features and is developed in its own repository.

#### Installing from source

Pamac uses [Meson](http://mesonbuild.com/index.html) build system.
In the source directory run:

`mkdir builddir && cd builddir`

`meson setup --prefix=/usr --sysconfdir=/etc --buildtype=release`

`meson compile`

`sudo meson install`

#### Translation

If you want to contribute in Pamac translations, use [Transifex](https://www.transifex.com/manjarolinux/manjaro-pamac).
