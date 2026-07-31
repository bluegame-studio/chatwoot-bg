json.source_id resource.source_id
json.source_name resource.source_name
json.page_id resource.inbox.channel.page_id if resource.inbox.facebook?
json.inbox do
  json.partial! 'api/v1/models/inbox_slim', formats: [:json], resource: resource.inbox
end
