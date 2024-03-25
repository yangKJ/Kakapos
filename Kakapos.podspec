#
# Be sure to run 'pod lib lint Kakapos.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'Kakapos'
  s.version          = '1.0.6'
  s.summary          = 'It is a filter infused video tool that supports network and local urls, as well as album videos.'
  
  # This description is used to generate tags and improve search results.
  #   * Think: What does it do? Why did you write it? What is the focus?
  #   * Try to keep it short, snappy and to the point.
  #   * Write the description between the DESC delimiters below.
  #   * Finally, don't worry about the indent, CocoaPods strips it!
  
  s.homepage         = 'https://github.com/yangKJ/Kakapos'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Condy' => 'yangkj310@gmail.com' }
  s.source           = { :git => 'https://github.com/yangKJ/Kakapos.git', :tag => s.version }
  
  s.swift_version    = '5.0'
  s.requires_arc     = true
  s.static_framework = true
  s.ios.deployment_target = '10.0'
  s.macos.deployment_target = '10.13'
  s.pod_target_xcconfig = { 'SWIFT_VERSION' => '5.0' }
  
  s.source_files = 'Sources/*.swift'
  s.weak_frameworks = 'CoreVideo', 'AVFoundation'
  
end
