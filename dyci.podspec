Pod::Spec.new do |s|
  s.name         = "dyci"
  s.version      = "0.1.5.20130602"
  s.summary      = "Dynamic code injection tool. Allows to inject code at runtime."

  s.homepage     = "https://github.com/DyCI/dyci-main"
  s.license      = 'MIT'

  s.author       = { "Paul Taykalo" => "tt.kilew@gmail.com" }

  s.source       = { :git => "https://github.com/DyCI/dyci-main.git", :tag => 'v0.1.5.1' }

  s.platform     = :ios, '4.3'

  s.source_files = 'Dynamic Code Injection/dyci/Classes/*.{h,m}'
  s.requires_arc = true

  #...

  s.subspec 'Injections' do |sp|
    sp.source_files = 'Dynamic Code Injection/dyci/Classes/Injections/*.{h,m}'
    sp.compiler_flags = '-fobjc-no-arc'
    sp.requires_arc = false
  end

  s.subspec 'Helpers' do |sp|
    sp.source_files = 'Dynamic Code Injection/dyci/Classes/{FileWatcher,Categories,Notifications}/*.{h,m}'
  end
 
end
