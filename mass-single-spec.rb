#PURPOSE: Takes a path to a spec file that has been changed and runs a single spec from the file
parsed_path = ARGV[0].split('/')
module_name = parsed_path[1]
parsed_path.shift(2)
spec_path = parsed_path.join('/')

p "Running single_spec on module - #{module_name} and spec - #{spec_path}"

%x(bundle exec rake single_spec[#{module_name}] SPEC=#{spec_path})