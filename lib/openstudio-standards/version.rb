module OpenstudioStandards
  def self.git_revision
    cmd = 'git'
    exts = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';') : ['']
    ENV['PATH'].split(File::PATH_SEPARATOR).each do |path|
      exts.each do |ext|
        exe = "#{path}/#{cmd}#{ext}"
        if File.executable?(exe)
          revision = `"#{exe}" -C "#{__dir__}" rev-parse --short HEAD`
          return revision.strip!
        end
      end
    end
    return 'git-not-found-on-this-system'
  end
  VERSION = '0.8.4'.freeze
end
