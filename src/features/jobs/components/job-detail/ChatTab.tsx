/**
 * ChatTab — Embedded job chat channel view.
 * Extracted from JobDetailPage.
 *
 * Fetches the job's auto-created channel and renders the full message view
 * inline. If no channel exists yet, shows a prompt to start chatting.
 */

import { useQuery } from '@tanstack/react-query';
import { MessageSquare } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { PageSpinner } from '../../../../components/ui/Spinner';
import { useAuthStore } from '../../../../stores/auth-store';
import { getInbox } from '../../../../api/chat';
import { ChatMessageView } from '../../../chat/components/ChatMessageView';

export function ChatTab({ jobId, jobNumber }: { jobId: number; jobNumber: string }) {
  const { user } = useAuthStore();
  const navigate = useNavigate();

  // Find the job's channel from the inbox
  const { data: inbox, isLoading } = useQuery({
    queryKey: ['chat-inbox'],
    queryFn: () => getInbox(),
  });

  const jobChannel = inbox?.channels?.find(
    (c) => c.channel_type === 'job' && c.job_id === jobId
  );

  if (isLoading) return <PageSpinner label="Loading chat..." />;

  if (!jobChannel) {
    return (
      <div className="text-center py-12 px-4">
        <MessageSquare className="h-8 w-8 text-gray-300 mx-auto mb-2" />
        <p className="text-sm text-gray-500 dark:text-gray-400">No chat channel yet</p>
        <p className="text-xs text-gray-400 mt-1 mb-3">
          Chat channels are automatically created when messages are sent.
        </p>
        <button
          onClick={() => navigate('/chat/inbox')}
          className="text-xs text-primary-600 dark:text-primary-400 hover:underline"
        >
          Go to Chat Inbox
        </button>
      </div>
    );
  }

  return (
    <div className="h-[500px] sm:h-[600px] border border-border rounded-lg overflow-hidden">
      <ChatMessageView
        channelId={jobChannel.id}
        currentUserId={user!.id}
        channelName={`${jobNumber} Chat`}
      />
    </div>
  );
}
