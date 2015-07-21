Pod::Spec.new do |spec|
  spec.name         = 'CKSIncrementalStore'
  spec.version      = '0.5.2'
  spec.license      = { :type => 'MIT' }
  spec.homepage     = 'https://github.com/nofelmahmood/CKSIncrementalStore'
  spec.authors      = { 'Nofel Mahmood' => 'nofelmehmood@gmail.com' }
  spec.social_media_url = "https://twitter.com/NofelMahmood"
  spec.summary      = 'CloudKit spreading awesomeness through CoreData.'
  spec.source       = { :git => 'https://github.com/nofelmahmood/CKSIncrementalStore.git', :tag => '0.5.2' }
  spec.source_files = 'CKSIncrementalStore'
  spec.ios.deployment_target = '8.0'
  spec.osx.deployment_target = '10.10'
  spec.framework    = 'CoreData'
  spec.framework    = 'CloudKit'
end