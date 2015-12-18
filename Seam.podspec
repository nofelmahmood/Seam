Pod::Spec.new do |s|
  s.name = 'Seam'
  s.version = '0.6'
  s.license = 'MIT'
  s.summary = 'Seamless CloudKit Sync with CoreData'
  s.homepage = 'https://github.com/nofelmahmood/Seam'
  s.social_media_url = 'http://twitter.com/NofelMahmood'
  s.authors = { 'Nofel Mahmood' => 'nofelmehmood@gmail.com' }
  s.source = { :git => 'https://github.com/nofelmahmood/Seam.git', :branch => 'Improve-Store' }

  s.ios.deployment_target = '8.0'
  s.osx.deployment_target = '10.10'

  s.source_files = 'Source/**/*.swift'

  s.framework    = 'CoreData'
  s.framework    = 'CloudKit'

  s.requires_arc = true
end
