#!/bin/ruby
#Returns your currently active VMS in floaty to the most previous snapshot.
@PRUNED_LIST = []
@LIST=%x(floaty list --active)
@LIST = @LIST.split("\n- ")

@LIST.each do |node|
  if node.include? "roles:"
    node = node.slice(0..(node.index('.net')+ ('.net'.length - 1)))
    @PRUNED_LIST.push(node)
  end
end

@PRUNED_LIST.each do |fqdn|
  node = fqdn.slice(0..(fqdn.index('.deliver') -1))
  query = Hash.new
  query = eval(%x(floaty query #{fqdn}))
  snaps = query[node]["snapshots"]
  unless snaps.nil?
    recent = snaps.last
    p "Reverting to most recent snapshot #{recent} on #{fqdn}"
    %x(floaty revert #{fqdn} #{recent})
  end
end
