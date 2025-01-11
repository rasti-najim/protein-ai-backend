insert into storage.buckets (id, name)
values ('temp', 'temp');

create policy "Allow authenticated uploads to temp bucket"
on storage.objects for insert
to authenticated
with check (
    bucket_id = 'temp'
);
