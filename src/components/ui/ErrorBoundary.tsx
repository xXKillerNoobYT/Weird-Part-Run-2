/**
 * ErrorBoundary — catches unhandled render errors in child components.
 *
 * Place at the AppShell level to prevent the entire app from white-screening.
 * When a child component throws during render, this shows a friendly error
 * screen with a "Try Again" button instead of a blank page.
 */

import { Component, type ErrorInfo, type ReactNode } from 'react';
import { ErrorFallback } from './ErrorFallback';

interface Props {
    children: ReactNode;
    /** Optional context label (e.g. "Dashboard") for error tracking */
    label?: string;
}

interface State {
    hasError: boolean;
    error: Error | null;
}

export class ErrorBoundary extends Component<Props, State> {
    constructor(props: Props) {
        super(props);
        this.state = { hasError: false, error: null };
    }

    static getDerivedStateFromError(error: Error): State {
        return { hasError: true, error };
    }

    componentDidCatch(error: Error, errorInfo: ErrorInfo) {
        // Log to console for debugging — production should hook into a service
        console.error(
            `[ErrorBoundary${this.props.label ? ` — ${this.props.label}` : ''}]`,
            error,
            errorInfo.componentStack,
        );
    }

    handleRetry = () => {
        this.setState({ hasError: false, error: null });
    };

    render() {
        if (this.state.hasError) {
            return (
                <ErrorFallback
                    message="This section encountered an error"
                    description="An unexpected error occurred. Click below to try again."
                    error={this.state.error}
                    onRetry={this.handleRetry}
                />
            );
        }

        return this.props.children;
    }
}
