﻿// Copyright (c) Microsoft. All rights reserved.
// Licensed under the MIT license. See LICENSE file in the project root for full license information.

using System;
using System.Runtime.Serialization;

namespace Microsoft.Build.Tasks.ResourceHandling
{
    internal sealed class PreserializedResourceWriterRequiredException : Exception
    {
        public PreserializedResourceWriterRequiredException() { }
    }
}
