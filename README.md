CLI front end of [libpamac](https://gitlab.manjaro.org/applications/libpamac)

#### Installing from source

Pamac uses [Meson](http://mesonbuild.com/index.html) build system.
In the source directory run:

`mkdir builddir && cd builddir`

`meson setup --prefix=/usr --sysconfdir=/etc --buildtype=release`

`meson compile`

`sudo meson install`

#### Translation

If you want to contribute in Pamac translations, use [Transifex](https://www.transifex.com/manjarolinux/manjaro-pamac).
