create policy "Allow authenticated select from temp bucket"
on storage.objects for select
to authenticated
using (
    bucket_id = 'temp'
);
