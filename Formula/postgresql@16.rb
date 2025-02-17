# PostgreSQL formula which supports extensions.
#
# - This formula is not keg-only, so it can be linked into the Homebrew prefix.
# - This formula loads extensions from `$HOMEBREW_PREFIX/share/postgresql@16`
#   and `$HOMEBREW_PREFIX/lib/postgresql@16`, instead of in the keg directory.
#
#   This makes it possible to install extensions like PostGIS for PostgreSQL
#   16, by linking them into the same directories.
#
#
# Generated with:
#     brew tap --force homebrew/homebrew-core
#     brew extract homebrew/homebrew-core/postgresql@16 MercuryTechnologies/homebrew-tap
#
class PostgresqlAT16 < Formula
  desc "Object-relational database system"
  homepage "https://www.postgresql.org/"
  url "https://ftp.postgresql.org/pub/source/v16.3/postgresql-16.3.tar.bz2"
  sha256 "331963d5d3dc4caf4216a049fa40b66d6bcb8c730615859411b9518764e60585"
  license "PostgreSQL"

  livecheck do
    url "https://ftp.postgresql.org/pub/source/"
    regex(%r{href=["']?v?(16(?:\.\d+)+)/?["' >]}i)
  end

  # https://www.postgresql.org/support/versioning/
  deprecate! date: "2028-11-09", because: :unsupported

  depends_on "pkg-config" => :build
  depends_on "gettext"
  depends_on "icu4c"

  # GSSAPI provided by Kerberos.framework crashes when forked.
  # See https://github.com/Homebrew/homebrew-core/issues/47494.
  depends_on "krb5"

  depends_on "lz4"
  depends_on "openssl@3"
  depends_on "readline"
  depends_on "zstd"

  uses_from_macos "libxml2"
  uses_from_macos "libxslt"
  uses_from_macos "openldap"
  uses_from_macos "perl"

  on_linux do
    depends_on "linux-pam"
    depends_on "util-linux"
  end

  def install
    ENV.delete "PKG_CONFIG_LIBDIR"
    ENV.prepend "LDFLAGS", "-L#{Formula["openssl@3"].opt_lib} -L#{Formula["readline"].opt_lib}"
    ENV.prepend "CPPFLAGS", "-I#{Formula["openssl@3"].opt_include} -I#{Formula["readline"].opt_include}"

    # Fix 'libintl.h' file not found for extensions
    ENV.prepend "LDFLAGS", "-L#{Formula["gettext"].opt_lib}"
    ENV.prepend "CPPFLAGS", "-I#{Formula["gettext"].opt_include}"

    # We need to do a fairly complex dance with the build system here.
    #
    # We want PostgreSQL to load libraries and extensions from
    # `/opt/homebrew/lib/postgresql@16` and
    # `/opt/homebrew/share/postgresql@16`, but Homebrew will error if you try
    # to actually install into those locations.
    #
    # So we tell the `./configure` and `make` build scripts that those are the
    # library directories and data directories respectively, but when we do
    # `make install-world` we give it the paths in
    # `/opt/homebrew/opt/postgresql@16` that Homebrew will actually let us
    # install to.
    #
    # Then, when the formula is linked into the Homebrew prefix, the paths
    # installed to `/opt/homebrew/opt/postgresql@16/share/postgresql@16` will
    # be symlinked and available at `/opt/homebrew/share/postgresql@16`.
    #
    # This is important because it allows extensions like PostGIS to also link
    # files there for PostgreSQL to load.
    #
    # Note: Various parts of the build system refer to the `datadir` and
    # `sharedir`. These are the same thing.

    datadir = "#{HOMEBREW_PREFIX}/share/#{name}"
    libdir = "#{HOMEBREW_PREFIX}/lib/#{name}"

    args = std_configure_args + %W[
      --datadir=#{datadir}
      --libdir=#{libdir}
      --includedir=#{opt_include}
      --sysconfdir=#{etc}
      --docdir=#{doc}
      --enable-nls
      --enable-thread-safety
      --with-gssapi
      --with-icu
      --with-ldap
      --with-libxml
      --with-libxslt
      --with-lz4
      --with-zstd
      --with-openssl
      --with-pam
      --with-perl
      --with-uuid=e2fs
      --with-extra-version=\ (#{tap.user})
    ]
    if OS.mac?
      args += %w[
        --with-bonjour
        --with-tcl
      ]
    end

    # PostgreSQL by default uses xcodebuild internally to determine this,
    # which does not work on CLT-only installs.
    args << "PG_SYSROOT=#{MacOS.sdk_path}" if OS.mac? && MacOS.sdk_root_needed?

    system "./configure", *args

    # Work around busted path magic in Makefile.global.in. This can't be specified
    # in ./configure, but needs to be set here otherwise install prefixes containing
    # the string "postgres" will get an incorrect pkglibdir.
    # See https://github.com/Homebrew/homebrew-core/issues/62930#issuecomment-709411789
    system "make", "datadir=#{datadir}",
                   "pkglibdir=#{libdir}",
                   "pkgincludedir=#{opt_include}/postgresql",
                   "includedir_server=#{opt_include}/postgresql/server"
    system "make", "install-world", "datadir=#{pkgshare}",
                                    "libdir=#{lib}/#{name}",
                                    "pkglibdir=#{lib}/#{name}",
                                    "includedir=#{include}",
                                    "pkgincludedir=#{include}/postgresql",
                                    "includedir_server=#{include}/postgresql/server",
                                    "includedir_internal=#{include}/postgresql/internal"
  end

  def post_install
    (var/"log").mkpath
    postgresql_datadir.mkpath

    # Don't initialize database, it clashes when testing other PostgreSQL versions.
    return if ENV["HOMEBREW_GITHUB_ACTIONS"]

    system "#{bin}/initdb", "--locale=C", "-E", "UTF-8", postgresql_datadir unless pg_version_exists?
  end

  def postgresql_datadir
    var/name
  end

  def postgresql_log_path
    var/"log/#{name}.log"
  end

  def pg_version_exists?
    (postgresql_datadir/"PG_VERSION").exist?
  end

  def caveats
    <<~EOS
      This formula has created a default database cluster with:
        initdb --locale=C -E UTF-8 #{postgresql_datadir}
      For more details, read:
        https://www.postgresql.org/docs/#{version.major}/app-initdb.html
    EOS
  end

  service do
    run [opt_bin/"postgres", "-D", f.postgresql_datadir]
    environment_variables LC_ALL: "C"
    keep_alive true
    log_path f.postgresql_log_path
    error_log_path f.postgresql_log_path
    working_dir HOMEBREW_PREFIX
  end

  test do
    sharedir = "#{HOMEBREW_PREFIX}/share/#{name}"
    libdir = "#{HOMEBREW_PREFIX}/lib/#{name}"

    system "#{bin}/initdb", testpath/"test" unless ENV["HOMEBREW_GITHUB_ACTIONS"]
    assert_equal sharedir, shell_output("#{bin}/pg_config --sharedir").chomp
    assert_equal libdir, shell_output("#{bin}/pg_config --pkglibdir").chomp
    assert_equal libdir, shell_output("#{bin}/pg_config --libdir").chomp
    assert_equal (opt_include/"postgresql").to_s, shell_output("#{bin}/pg_config --pkgincludedir").chomp
    assert_equal (opt_include/"postgresql/server").to_s, shell_output("#{bin}/pg_config --includedir-server").chomp
    assert_match "-I#{Formula["gettext"].opt_include}", shell_output("#{bin}/pg_config --cppflags")
  end
end
