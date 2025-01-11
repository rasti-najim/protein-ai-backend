CREATE POLICY "Select temp" ON storage.objects
FOR SELECT
TO authenticated
USING (auth.uid() = storage.owner(object_id));
