Pod::Spec.new do |spec|
  spec.name         = 'Seam'
  spec.version      = '0.6'
  spec.license      = { :type => 'MIT' }
  spec.homepage     = 'https://github.com/nofelmahmood/Seam'
  spec.authors      = { 'Nofel Mahmood' => 'nofelmehmood@gmail.com' }
  spec.social_media_url = "https://twitter.com/NofelMahmood"
  spec.summary      = 'CloudKit spreading awesomeness through CoreData.'
  spec.source       = { :git => 'https://github.com/nofelmahmood/Seam.git', :tag => "0.6"}
  spec.ios.deployment_target = '8.3'
  spec.osx.deployment_target = '10.10'
  spec.header_dir   = 'Seam'
  spec.source_files = 'Seam/**/*.{h,swift}'
  spec.framework    = 'CoreData'
  spec.framework    = 'CloudKit'
end
