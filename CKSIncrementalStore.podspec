Pod::Spec.new do |s|
  s.name     = 'CKSIncrementalStore'
  s.version  = '0.5'
  s.license  = 'MIT'
  s.homepage =  'https://github.com/CloudKitSpace/CKSIncrementalStore'
  s.summary  = "CloudKit spreading awesomeness through CoreData."
  s.authors  = { 'Nofel Mahmood' =>
                 'nofelmehmood@gmail.com' }
  s.social_media_url = "https://twitter.com/NofelMahmood"
  s.source   = { :git => 'https://github.com/CloudKitSpace/CKSIncrementalStore.git', :tag => '0.5' }
  s.source_files = 'CKSIncrementalStore/CKSIncrementalStore.swift'
  s.ios.deployment_target = '8.0'
  s.osx.deployment_target = '10.10'
  s.framework  = 'CoreData'
  s.framework  = 'CloudKit'

end
